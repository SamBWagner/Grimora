#!/usr/bin/env python3
"""
process_export.py

Turns the raw Apple Notes export (produced by export_grimora_notes.command)
into ready-to-hand-off PBI markdown files under tasks/inbox/.

Rules:
  - A note whose title contains ANY emoji (checkmark or otherwise) is
    considered already triaged/handled and is skipped.
  - Everything else gets a markdown file with the note's body (converted
    from Apple Notes' HTML to markdown) and any attachments pulled in
    alongside it. HEIC/HEIF photos are converted to JPEG since most AI
    agents can't read HEIC. Other image types are copied as-is.
  - Re-running is safe: pending notes get their PBI file regenerated
    (so edits in Notes are picked up), nothing is ever deleted.

Usage:
    python3 process_export.py

Run this from anywhere -- it locates the repo root from its own path.
"""

import csv
import re
import shutil
import sys
from pathlib import Path

from bs4 import BeautifulSoup
from markdownify import markdownify as html_to_md
from PIL import Image
import pillow_heif

pillow_heif.register_heif_opener()

REPO_ROOT = Path(__file__).resolve().parents[2]
EXPORT_ROOT = REPO_ROOT / "tasks" / "_notes_export"
RAW_DIR = EXPORT_ROOT / "raw"
MANIFEST = EXPORT_ROOT / "manifest.tsv"
INBOX_DIR = REPO_ROOT / "tasks" / "inbox"
IMAGES_DIR = INBOX_DIR / "images"

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".tiff", ".bmp", ".webp"}
HEIC_EXTS = {".heic", ".heif"}

# Broad emoji / pictographic ranges, including the checkmark block and
# variation selectors / ZWJ used to combine emoji.
EMOJI_PATTERN = re.compile(
    "["
    "\U0001F1E6-\U0001F1FF"  # regional indicators (flags)
    "\U0001F300-\U0001FAFF"  # symbols, pictographs, supplemental symbols
    "←-⇿"          # arrows (includes some used as emoji)
    "⌀-⏿"          # misc technical (includes watch/hourglass etc.)
    "①-⓿"          # enclosed alphanumerics
    "■-◿"          # geometric shapes
    "☀-➿"          # misc symbols + dingbats (includes checkmarks)
    "⬀-⯿"          # misc symbols and arrows (star, etc.)
    "️"                 # variation selector-16 (emoji presentation)
    "‍"                 # zero-width joiner
    "]"
)


def has_emoji(title: str) -> bool:
    return bool(EMOJI_PATTERN.search(title))


def slugify(title: str) -> str:
    slug = title.strip().lower()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug or "untitled"


def unique_slug(base: str, taken: set) -> str:
    if base not in taken:
        taken.add(base)
        return base
    n = 2
    while f"{base}-{n}" in taken:
        n += 1
    taken.add(f"{base}-{n}")
    return f"{base}-{n}"


def html_body_to_markdown(body_html: str) -> str:
    """Convert Notes' HTML body to markdown, dropping <img> tags entirely.
    Apple Notes inlines photo/screenshot data as base64 data: URIs right
    in the HTML, and markdownify will happily dump that (often 100s of KB
    of base64 text) straight into the markdown. We already pull the real
    image files out via the attachments export, so the images are handled
    separately -- the inline tag is pure bloat here."""
    soup = BeautifulSoup(body_html, "html.parser")
    for img in soup.find_all("img"):
        img.decompose()
    return html_to_md(str(soup), heading_style="ATX")


def strip_title_line(body_md: str, title: str) -> str:
    """Apple Notes stores the title as the first line of the body.
    Remove it (and any leading blank lines) so we don't repeat it."""
    lines = body_md.splitlines()
    if lines and lines[0].strip().lstrip("#").strip() == title.strip():
        lines = lines[1:]
    while lines and not lines[0].strip():
        lines = lines[1:]
    return "\n".join(lines).strip()


PROMPT_HEADING_RE = re.compile(r"^#{1,6}\s*prompt\s*$|^\*\*prompt\*\*$", re.IGNORECASE)


def strip_leading_prompt_heading(body_md: str) -> str:
    """Sam's own note convention puts a "Prompt" heading right after the
    title. We already render our own "## Problem" heading right before
    this text, so drop his heading to avoid two headings back to back."""
    lines = body_md.splitlines()
    if lines and PROMPT_HEADING_RE.match(lines[0].strip()):
        lines = lines[1:]
    while lines and not lines[0].strip():
        lines = lines[1:]
    return "\n".join(lines).strip()


def convert_image(src: Path, dest_dir: Path, dest_stem: str) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    ext = src.suffix.lower()
    if ext in HEIC_EXTS:
        img = Image.open(src).convert("RGB")
        dest = dest_dir / f"{dest_stem}.jpg"
        img.save(dest, "JPEG", quality=92)
        return dest
    else:
        dest = dest_dir / f"{dest_stem}{ext}"
        shutil.copyfile(src, dest)
        return dest


def copy_other_attachment(src: Path, dest_dir: Path, dest_stem: str) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{dest_stem}{src.suffix}"
    shutil.copyfile(src, dest)
    return dest


def main():
    if not MANIFEST.exists():
        print(f"No manifest found at {MANIFEST}.")
        print("Run export_grimora_notes.command first (double-click it in Finder).")
        sys.exit(1)

    INBOX_DIR.mkdir(parents=True, exist_ok=True)

    # Only guards against two DIFFERENT notes in this run slugifying to the
    # same name. Pre-existing files are intentionally NOT preloaded here so
    # re-running the pipeline on an already-exported note overwrites its
    # PBI file in place instead of creating a "-2" duplicate.
    taken_slugs = set()

    processed, skipped_done, skipped_missing = [], [], []

    with open(MANIFEST, newline="", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        rows = [r for r in reader if r]

    for row in rows:
        if len(row) < 3:
            continue
        note_id, title, modified = row[0], row[1], row[2]
        note_dir = RAW_DIR / note_id
        title_file = note_dir / "title.txt"
        body_file = note_dir / "body.html"

        if not title_file.exists() or not body_file.exists():
            skipped_missing.append(title)
            continue

        actual_title = title_file.read_text(encoding="utf-8").strip()

        if has_emoji(actual_title):
            skipped_done.append(actual_title)
            continue

        body_html = body_file.read_text(encoding="utf-8")
        body_md = html_body_to_markdown(body_html)
        body_md = strip_title_line(body_md, actual_title)
        body_md = strip_leading_prompt_heading(body_md)

        slug = unique_slug(slugify(actual_title), taken_slugs)

        attachments_dir = note_dir / "attachments"
        image_lines, other_lines = [], []
        if attachments_dir.exists():
            atts = sorted(attachments_dir.iterdir())
            img_i, other_i = 0, 0
            for att in atts:
                if not att.is_file():
                    continue
                ext = att.suffix.lower()
                if ext in IMAGE_EXTS:
                    img_i += 1
                    dest = convert_image(att, IMAGES_DIR, f"{slug}-{img_i:02d}")
                    image_lines.append(f"![{actual_title} - image {img_i}](images/{dest.name})")
                else:
                    other_i += 1
                    dest = copy_other_attachment(att, IMAGES_DIR, f"{slug}-attachment-{other_i:02d}")
                    other_lines.append(f"- [{dest.name}](images/{dest.name})")

        lines = [
            "- [ ] Not started",
            "",
            f"# {actual_title}",
            "",
            "## Problem",
            "",
            body_md if body_md else "*(no additional text in note)*",
        ]
        if image_lines:
            lines += ["", "## Screenshot" + ("s" if len(image_lines) > 1 else ""), ""]
            lines += image_lines
        if other_lines:
            lines += ["", "## Attachments", ""]
            lines += other_lines
        lines += [
            "",
            "## Source",
            "",
            f"Apple Notes -> Grimora -> \"{actual_title}\" (modified {modified})",
            "",
        ]

        out_path = INBOX_DIR / f"{slug}.md"
        out_path.write_text("\n".join(lines), encoding="utf-8")
        processed.append((actual_title, out_path.name))

    print(f"Processed {len(processed)} pending note(s) into {INBOX_DIR}:")
    for title, fname in processed:
        print(f"  - {title}  ->  tasks/inbox/{fname}")
    if skipped_done:
        print(f"\nSkipped {len(skipped_done)} note(s) already marked done/tagged (emoji in title):")
        for title in skipped_done:
            print(f"  - {title}")
    if skipped_missing:
        print(f"\nWarning: {len(skipped_missing)} note(s) in manifest had no raw data on disk:")
        for title in skipped_missing:
            print(f"  - {title}")


if __name__ == "__main__":
    main()
