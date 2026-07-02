#!/usr/bin/env python3
"""Rebuild the Scry test-corpus catalog (ScryCorpus/catalog.json.gz).

The catalog is a real Scryfall snapshot the recognition tests resolve against —
never a database built from the expected answers (see ScryCorpus/README.md,
"Black-box principle"). For every entry in manifest.json and
scenes-manifest.json this script fetches:

  1. every printing of the card's name (so name searches face real reprints), and
  2. the full set the entry's printing belongs to (so set-size lookups like the
     old-frame `6/249` total are real), skipped with a warning above
     --max-set-size cards to keep the fixture reasonable.

The result is unioned with the existing catalog (cards are never dropped),
deduplicated by Scryfall id, deterministically sorted, and gzip-compressed.

Usage:
  Tools/scry_build_corpus_catalog.py            # rebuild + verify
  Tools/scry_build_corpus_catalog.py --check    # verify existing catalog only

Scryfall is fetched via curl (python's urllib lacks CA certs in some dev
environments); requests are spaced ~120ms per Scryfall's rate-limit guidance.
"""

import argparse
import gzip
import json
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CORPUS_DIR = REPO_ROOT / "GrimoraKit/Tests/GrimoraCoreTests/ScryCorpus"
CATALOG_PATH = CORPUS_DIR / "catalog.json.gz"
MANIFESTS = [CORPUS_DIR / "manifest.json", CORPUS_DIR / "scenes-manifest.json"]
API = "https://api.scryfall.com"


def curl_json(url: str) -> dict:
    payload: dict = {}
    for attempt in range(4):
        time.sleep(0.15)
        try:
            out = subprocess.run(["curl", "-s", url], capture_output=True, check=True)
            payload = json.loads(out.stdout)
        except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
            # Transient network blips (curl exit 6 = DNS) shouldn't kill a
            # half-hour fetch — back off and retry like a rate limit.
            wait = 10 * (attempt + 1)
            print(f"  fetch failed ({error}); retrying in {wait}s…")
            time.sleep(wait)
            continue
        if payload.get("object") == "error" and "rate-limited" in str(payload.get("details", "")):
            wait = 65 * (attempt + 1)
            print(f"  rate-limited; backing off {wait}s…")
            time.sleep(wait)
            continue
        return payload
    return payload


def search_all(query: str) -> list[dict]:
    cards: list[dict] = []
    url = f"{API}/cards/search?unique=prints&q=" + urllib.parse.quote(query)
    while url:
        page = curl_json(url)
        if page.get("object") == "error":
            # A name with zero results is a manifest mistake worth surfacing.
            raise SystemExit(f"Scryfall error for {query!r}: {page.get('details')}")
        cards += page["data"]
        url = page.get("next_page")
    return cards


def load_entries() -> list[dict]:
    entries = []
    for manifest in MANIFESTS:
        if manifest.exists():
            entries += json.loads(manifest.read_text())["entries"]
    return entries


def load_existing() -> list[dict]:
    if not CATALOG_PATH.exists():
        return []
    with gzip.open(CATALOG_PATH, "rt") as f:
        return json.load(f)


def build(max_set_size: int) -> list[dict]:
    entries = load_entries()
    names = sorted({e["name"] for e in entries})
    sets = sorted({e["setCode"].lower() for e in entries})

    merged = {c["id"]: c for c in load_existing()}
    before = len(merged)

    for name in names:
        printings = search_all(f'!"{name}"')
        for card in printings:
            merged.setdefault(card["id"], card)
        print(f"  {name}: {len(printings)} printings")

    for set_code in sets:
        meta = curl_json(f"{API}/sets/{set_code}")
        count = meta.get("card_count", 0)
        if count > max_set_size:
            print(f"  set {set_code}: SKIPPED full-set fetch ({count} > {max_set_size} cards); "
                  "set-size lookups for this set may be approximate")
            continue
        cards = search_all(f"set:{set_code}")
        for card in cards:
            merged.setdefault(card["id"], card)
        print(f"  set {set_code}: {len(cards)} cards")

    cards = sorted(merged.values(), key=lambda c: (c["set"], c.get("collector_number", ""), c["id"]))
    print(f"catalog: {before} existing -> {len(cards)} merged")
    return cards


def check(cards: list[dict]) -> bool:
    keys = {(c["set"].lower(), c.get("collector_number", "")) for c in cards}
    ok = True
    for entry in load_entries():
        key = (entry["setCode"].lower(), entry["collectorNumber"])
        if key not in keys:
            print(f"MISSING from catalog: {entry['name']} [{key[0]} {key[1]}]")
            ok = False
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="verify the existing catalog covers every manifest entry; no fetching")
    parser.add_argument("--max-set-size", type=int, default=450,
                        help="skip full-set fetches for sets larger than this (default 450)")
    args = parser.parse_args()

    if args.check:
        cards = load_existing()
        if not cards:
            print(f"no catalog at {CATALOG_PATH}")
            return 1
        return 0 if check(cards) else 1

    cards = build(args.max_set_size)
    with gzip.open(CATALOG_PATH, "wt", compresslevel=9) as f:
        json.dump(cards, f, separators=(",", ":"))
    print(f"wrote {CATALOG_PATH} ({CATALOG_PATH.stat().st_size // 1024} KB)")
    return 0 if check(cards) else 1


if __name__ == "__main__":
    sys.exit(main())
