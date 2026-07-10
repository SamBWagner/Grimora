# Notes -> PBI export

Turns Apple Notes in the "Grimora" folder into ready-to-hand-off PBI files
in `tasks/inbox/`, without needing anyone to click through Notes by hand.

## How it works

1. **`export_grimora_notes.command`** (double-click in Finder) runs the
   AppleScript in this folder. It's the only step that has to happen on
   this Mac, since it's the only thing that can actually talk to Notes.app.
   It dumps every note's title, HTML body, and attachments (in their
   native format) into `tasks/_notes_export/raw/`. First run will prompt
   for permission to control Notes/Finder -- approve it once.

2. **`process_export.py`** reads that raw dump and writes the final PBI
   files. Run it with `python3 tools/notes-pbi-export/process_export.py`
   from anywhere with the repo checked out (Claude can run this part
   directly, no GUI needed). Rules it applies:
   - A note whose title has ANY emoji (✅, 🧊, etc.) is treated as already
     triaged and is skipped.
   - Everything else gets `tasks/inbox/<slug>.md` with the note body
     converted to markdown, plus any images in `tasks/inbox/images/`.
   - HEIC/HEIF photos are converted to JPEG (most AI agents can't read
     HEIC). Other image types are copied as-is.
   - Re-running is safe and idempotent: pending notes get their file
     regenerated so edits in Notes are picked up; nothing is deleted.

## Usage

Whenever there are new/edited notes in Grimora:

```
1. Double-click export_grimora_notes.command
2. python3 tools/notes-pbi-export/process_export.py
```

Requires `markdownify`, `beautifulsoup4`, and `pillow-heif` (`pip install
markdownify beautifulsoup4 pillow-heif`).

## Known limitations

- The AppleScript looks up the "Grimora" folder by name; if it's renamed
  this breaks.
- Emoji detection is a broad Unicode range regex, not exhaustive -- if a
  note is wrongly skipped/included, check `EMOJI_PATTERN` in
  `process_export.py`.
- Image placement in the markdown is always appended at the end, not
  inlined at the position it appeared in the original note.
