#!/usr/bin/env python3
"""Merge Grimora Scry harness captures into the Scry test corpus.

The GrimoraScry iOS harness saves each verdict-labeled scan into its
Documents/Captures folder as three files:

  <id>-still.jpg   the exact image the pipeline ran on (EXIF orientation kept)
  <id>-crop.jpg    the rectified card crop, baked upright
  <id>.json        sidecar: ground truth, verdict, and the engine's answer

Drag that folder off the phone (Finder → iPhone → Files → Grimora Scry) and
point this script at it. Per labeled capture it:

  1. copies the crop into ScryCorpus/images/<name-slug>-<set>-<number>[...].jpg
     and appends a manifest.json entry, and
  2. copies the still into ScryCorpus/scenes/<same>-fullres.jpg and appends a
     scenes-manifest.json entry,

with the expectation mapped from the verdict: correct → auto (omitted),
correct-via-candidate-pick → disambiguation, wrong → knownFailure. Unlabeled
captures (needsLabel) are skipped with a warning. Processed captures move to
<captures>/imported/ so re-runs are idempotent. Finishes by verifying catalog
coverage (scry_build_corpus_catalog.py --check) and printing the rebuild
command when new cards need fetching.

Usage:
  Tools/scry_import_captures.py ~/Downloads/Captures            # import
  Tools/scry_import_captures.py ~/Downloads/Captures --dry-run  # preview only
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CORPUS_DIR = REPO_ROOT / "GrimoraKit/Tests/GrimoraCoreTests/ScryCorpus"
IMAGES_DIR = CORPUS_DIR / "images"
SCENES_DIR = CORPUS_DIR / "scenes"
MANIFEST_PATH = CORPUS_DIR / "manifest.json"
SCENES_MANIFEST_PATH = CORPUS_DIR / "scenes-manifest.json"
CATALOG_CHECK = REPO_ROOT / "Tools/scry_build_corpus_catalog.py"


def slugify(name: str) -> str:
    # Apostrophes vanish rather than becoming separators ("Ajani's" → "ajanis"),
    # matching the existing corpus filenames.
    slug = re.sub(r"['’]", "", name.lower())
    slug = re.sub(r"[^a-z0-9]+", "-", slug).strip("-")
    return re.sub(r"-{2,}", "-", slug)


def strip_leading_zeros(collector_number: str) -> str:
    stripped = collector_number.lstrip("0")
    return stripped if stripped else "0"


def load_manifest(path: Path) -> dict:
    if path.exists():
        return json.loads(path.read_text())
    return {"entries": []}


def save_manifest(path: Path, manifest: dict) -> None:
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


def base_slug(capture: dict) -> str:
    truth = capture["groundTruth"]
    parts = [
        slugify(truth["name"]),
        truth["setCode"].lower(),
        strip_leading_zeros(truth["collectorNumber"]),
    ]
    slug = "-".join(parts)
    if capture.get("foil"):
        slug += "-foil"
    if capture.get("sleeved"):
        slug += "-sleeved"
    return slug


def unique_slug(slug: str, taken: set[str]) -> str:
    """Repeat photos of the same printing are legitimate growth — suffix them."""
    if slug not in taken:
        return slug
    counter = 2
    while f"{slug}-{counter}" in taken:
        counter += 1
    return f"{slug}-{counter}"


def expectation_for(capture: dict) -> str | None:
    """None means the default (auto)."""
    verdict = capture["verdict"]
    if verdict == "wrong":
        return "knownFailure"
    if verdict == "correct" and capture.get("pickedFromCandidates"):
        return "disambiguation"
    return None


def notes_for(capture: dict) -> str:
    engine = capture.get("engine") or {}
    engine_card = engine.get("card")
    answer = (
        f"{engine_card['name']} [{engine_card['setCode']} {engine_card['collectorNumber']}]"
        if engine_card
        else engine.get("confidence", "no result")
    )
    provenance = (
        f"GrimoraScry {capture['timestamp']}; "
        f"engine: {engine.get('method', '—')}/{engine.get('confidence', '—')} → {answer}"
    )
    user_notes = capture.get("notes")
    return f"{user_notes} — {provenance}" if user_notes else provenance


def manifest_entry(capture: dict, image_name: str) -> dict:
    truth = capture["groundTruth"]
    entry = {
        "image": image_name,
        "name": truth["name"],
        "setCode": truth["setCode"].lower(),
        "collectorNumber": strip_leading_zeros(truth["collectorNumber"]),
    }
    expectation = expectation_for(capture)
    if expectation:
        entry["expectation"] = expectation
    entry["foil"] = bool(capture.get("foil"))
    entry["sleeved"] = bool(capture.get("sleeved"))
    if capture.get("background"):
        entry["background"] = capture["background"]
    entry["notes"] = notes_for(capture)
    return entry


def scene_entry(capture: dict, image_name: str) -> dict:
    truth = capture["groundTruth"]
    entry = {
        "image": image_name,
        "name": truth["name"],
        "setCode": truth["setCode"].lower(),
        "collectorNumber": strip_leading_zeros(truth["collectorNumber"]),
    }
    expectation = expectation_for(capture)
    if expectation:
        entry["expectation"] = expectation
    if capture.get("foil"):
        entry["foil"] = True
    entry["notes"] = notes_for(capture)
    return entry


def import_captures(captures_dir: Path, dry_run: bool) -> int:
    sidecars = sorted(captures_dir.glob("*.json"))
    if not sidecars:
        print(f"No capture sidecars (*.json) found in {captures_dir}")
        return 1

    manifest = load_manifest(MANIFEST_PATH)
    scenes_manifest = load_manifest(SCENES_MANIFEST_PATH)
    taken_images = {Path(e["image"]).stem for e in manifest["entries"]}
    taken_scenes = {Path(e["image"]).stem for e in scenes_manifest["entries"]}
    imported_dir = captures_dir / "imported"

    imported = skipped = 0
    for sidecar in sidecars:
        capture = json.loads(sidecar.read_text())
        capture_id = capture.get("id", sidecar.stem)

        if capture.get("needsLabel") or not capture.get("groundTruth"):
            print(f"  ~ {capture_id}: unlabeled (needsLabel) — label the sidecar first, skipping")
            skipped += 1
            continue

        crop_path = captures_dir / f"{capture_id}-crop.jpg"
        still_path = captures_dir / f"{capture_id}-still.jpg"
        if not crop_path.exists() and not still_path.exists():
            print(f"  ~ {capture_id}: no crop or still next to the sidecar, skipping")
            skipped += 1
            continue

        slug = base_slug(capture)
        expectation = expectation_for(capture) or "auto"
        moves: list[tuple[Path, Path]] = []

        if crop_path.exists():
            crop_slug = unique_slug(slug, taken_images)
            taken_images.add(crop_slug)
            crop_name = f"{crop_slug}.jpg"
            manifest["entries"].append(manifest_entry(capture, crop_name))
            moves.append((crop_path, IMAGES_DIR / crop_name))
        else:
            print(f"  ~ {capture_id}: no crop (detection failed?) — importing the still only")

        if still_path.exists():
            scene_slug = unique_slug(f"{slug}-fullres", taken_scenes)
            taken_scenes.add(scene_slug)
            scene_name = f"{scene_slug}.jpg"
            scenes_manifest["entries"].append(scene_entry(capture, scene_name))
            moves.append((still_path, SCENES_DIR / scene_name))

        print(f"  + {capture_id} → {slug}  [{expectation}]")
        if not dry_run:
            for source, destination in moves:
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
            imported_dir.mkdir(exist_ok=True)
            for path in [sidecar, crop_path, still_path]:
                if path.exists():
                    shutil.move(str(path), imported_dir / path.name)
        imported += 1

    print(f"\n{'Would import' if dry_run else 'Imported'} {imported} capture(s), skipped {skipped}.")
    if imported == 0:
        return 0
    if dry_run:
        print("Dry run — nothing written.")
        return 0

    save_manifest(MANIFEST_PATH, manifest)
    save_manifest(SCENES_MANIFEST_PATH, scenes_manifest)
    print(f"Updated {MANIFEST_PATH.name} and {SCENES_MANIFEST_PATH.name}.")

    print("\nVerifying catalog coverage…")
    result = subprocess.run([sys.executable, str(CATALOG_CHECK), "--check"], cwd=REPO_ROOT)
    if result.returncode != 0:
        print(
            "\nNew cards are missing from the test catalog. Fetch their printings with:\n"
            f"  {CATALOG_CHECK.relative_to(REPO_ROOT)}\n"
            "(rate-limited Scryfall fetch — takes a few minutes), then run:\n"
            "  swift test --package-path GrimoraKit --filter 'ScryCorpusTests|ScrySceneTests'"
        )
        return result.returncode
    print("Catalog covers every entry. Run the tests:\n"
          "  swift test --package-path GrimoraKit --filter 'ScryCorpusTests|ScrySceneTests'")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("captures", type=Path,
                        help="the Captures folder dragged off the phone")
    parser.add_argument("--dry-run", action="store_true",
                        help="print what would be imported without writing anything")
    args = parser.parse_args()

    captures_dir = args.captures.expanduser()
    if not captures_dir.is_dir():
        print(f"Not a directory: {captures_dir}")
        return 1
    return import_captures(captures_dir, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
