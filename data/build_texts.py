"""Bundle the translations and tafsirs listed in data/texts.json into the app.

Every text comes from QuranEnc.com, whose terms let apps republish them on
conditions this pipeline exists to keep:

1. no modification, addition or deletion: the text and footnotes are copied
   byte for byte from QuranEnc's own database (only the container changes);
2. the publisher and QuranEnc.com are credited, and 3. the version is named:
   both travel with each text into the app, which shows them under it;
6. the text is kept at QuranEnc's latest version: `updates` reports any
   newer one (run it before every release) and `fetch` takes it.

The downloaded archives in data/raw/quranenc/ are verbatim and never edited.
Their SHA-256 is pinned in texts.json, and the build checks every text against
the Quran's own structure (quran-data.xml): 6236 ayahs, surah by surah, in
order, none empty. Any mismatch aborts.

Usage:
    py data/build_texts.py                 # build mobile/assets/texts/ from data/raw/quranenc/
    py data/build_texts.py --check         # CI: fail if the assets are stale
    py data/build_texts.py updates         # is any text behind QuranEnc? (exit 1 if so)
    py data/build_texts.py fetch [KEY...]  # download the current version, re-pin texts.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import sqlite3
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent
ROOT = DATA_DIR.parent
MANIFEST = DATA_DIR / "texts.json"
RAW_DIR = DATA_DIR / "raw" / "quranenc"
META_SRC = DATA_DIR / "raw" / "quran-data.xml"
ASSET_DIR = ROOT / "mobile" / "assets" / "texts"
CATALOG = "catalog.json"

API = "https://quranenc.com/api/v1"
BROWSE = "https://quranenc.com/en/browse/{key}"
USER_AGENT = "rafiq-build (Quran reader; bundles QuranEnc texts offline)"

TOTAL_VERSES = 6236
KINDS = {"translation", "tafsir"}
LANGUAGES = {"en", "fr", "ar"}


class BuildError(Exception):
    """A source or manifest inconsistency. Always fatal."""


def ayah_counts() -> list[int]:
    """Ayahs per surah, from the Tanzil metadata (independent of QuranEnc)."""
    suras = ET.parse(META_SRC).getroot().find("suras")
    if suras is None:
        raise BuildError(f"{META_SRC.name}: no <suras>")
    counts = [int(s.get("ayas", "0")) for s in suras.findall("sura")]
    if len(counts) != 114 or sum(counts) != TOTAL_VERSES:
        raise BuildError(f"{META_SRC.name}: {len(counts)} suras, {sum(counts)} ayahs")
    return counts


def load_manifest() -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    keys = set()
    for t in manifest["texts"]:
        key = t["key"]
        if key in keys:
            raise BuildError(f"texts.json: {key} listed twice")
        keys.add(key)
        if t["kind"] not in KINDS or t["language"] not in LANGUAGES or t["direction"] not in ("ltr", "rtl"):
            raise BuildError(f"texts.json: {key} has a bad kind, language or direction")
        for field in ("name", "credit"):
            if set(t[field]) != LANGUAGES or not all(v.strip() for v in t[field].values()):
                raise BuildError(f"texts.json: {key}.{field} needs en, fr and ar")
    return manifest


def read_rows(key: str, archive: bytes) -> list[tuple[str, str]]:
    """The (translation, footnotes) of every ayah, verbatim, validated against the Quran."""
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        members = [n for n in z.namelist() if n.endswith(".sqlite")]
        if len(members) != 1:
            raise BuildError(f"{key}.zip: expected one .sqlite, found {z.namelist()}")
        db_bytes = z.read(members[0])
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "t.sqlite"
        path.write_bytes(db_bytes)
        con = sqlite3.connect(path)
        try:
            rows = con.execute("select id, sura, aya, translation, footnotes from translations").fetchall()
        finally:
            con.close()

    rows.sort(key=lambda r: int(r[0]))
    if len(rows) != TOTAL_VERSES:
        raise BuildError(f"{key}: {len(rows)} ayahs, expected {TOTAL_VERSES}")
    expected = [(s, a) for s, n in enumerate(ayah_counts(), 1) for a in range(1, n + 1)]
    out: list[tuple[str, str]] = []
    for i, (row, (surah, ayah)) in enumerate(zip(rows, expected, strict=True), 1):
        rid, sura, aya, text, notes = row
        if (int(rid), int(sura), int(aya)) != (i, surah, ayah):
            raise BuildError(f"{key}: row {i} is {sura}:{aya} (id {rid}), expected {surah}:{ayah}")
        if not isinstance(text, str) or not text.strip():
            raise BuildError(f"{key}: {surah}:{ayah} has no text")
        out.append((text, notes or ""))
    return out


def build(manifest: dict) -> dict[str, bytes]:
    """Every asset file, by name: one per text, plus the catalog."""
    files: dict[str, bytes] = {}
    catalog = []
    for t in manifest["texts"]:
        key = t["key"]
        archive_path = RAW_DIR / f"{key}.zip"
        if not archive_path.exists():
            raise BuildError(f"{archive_path} missing; run: py data/build_texts.py fetch {key}")
        archive = archive_path.read_bytes()
        digest = hashlib.sha256(archive).hexdigest()
        if digest != t["sha256"]:
            raise BuildError(f"{key}.zip does not match the SHA-256 pinned in texts.json")
        meta = {
            "key": key,
            "kind": t["kind"],
            "language": t["language"],
            "direction": t["direction"],
            "name": t["name"],
            "credit": t["credit"],
            "version": t["version"],
            "updated": dt.datetime.fromtimestamp(t["last_update"], dt.UTC).date().isoformat(),
            "url": BROWSE.format(key=key),
        }
        catalog.append({**meta, "asset": f"assets/texts/{key}.json"})
        body = {**meta, "ayahs": [list(r) for r in read_rows(key, archive)]}
        files[f"{key}.json"] = _dump(body)
    files[CATALOG] = _dump(
        {
            "source": manifest["source"],
            "source_url": manifest["source_url"],
            "texts": catalog,
        }
    )
    return files


def _dump(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def _get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def _current(key: str) -> dict:
    return json.loads(_get(f"{API}/translations/updates?key={key}"))


def cmd_build(check: bool) -> int:
    files = build(load_manifest())
    if check:
        on_disk = {p.name: p.read_bytes() for p in ASSET_DIR.glob("*.json")}
        stale = sorted(n for n in files.keys() | on_disk.keys() if files.get(n) != on_disk.get(n))
        if stale:
            print(f"stale text assets ({', '.join(stale)}); run: py data/build_texts.py", file=sys.stderr)
            return 1
        print(f"text assets are up to date ({len(files) - 1} texts)")
        return 0
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    for old in ASSET_DIR.glob("*.json"):
        if old.name not in files:
            old.unlink()
    for name, data in files.items():
        (ASSET_DIR / name).write_bytes(data)
        print(f"wrote {name} ({len(data) / 1e6:.2f} MB)")
    return 0


def cmd_updates() -> int:
    behind = 0
    for t in load_manifest()["texts"]:
        cur = _current(t["key"])
        if (cur["version"], int(cur["last_update"])) != (t["version"], t["last_update"]):
            behind += 1
            print(f"{t['key']}: bundled {t['version']}, QuranEnc has {cur['version']}")
        else:
            print(f"{t['key']}: {t['version']} is current")
    if behind:
        print("run: py data/build_texts.py fetch KEY..., then rebuild and review the diff", file=sys.stderr)
    return 1 if behind else 0


def cmd_fetch(keys: list[str]) -> int:
    manifest = load_manifest()
    known = {t["key"]: t for t in manifest["texts"]}
    unknown = [k for k in keys if k not in known]
    if unknown:
        raise BuildError(f"not in texts.json: {', '.join(unknown)} (add the entry first)")
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    for key in keys or list(known):
        cur = _current(key)
        archive = _get(cur["database_url"])
        read_rows(key, archive)  # refuse to pin a broken download
        (RAW_DIR / f"{key}.zip").write_bytes(archive)
        t = known[key]
        t["version"], t["last_update"] = cur["version"], int(cur["last_update"])
        t["sha256"] = hashlib.sha256(archive).hexdigest()
        print(f"{key}: pinned {t['version']} ({len(archive) / 1e3:.0f} kB)")
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    MANIFEST.write_text(manifest_text, encoding="utf-8", newline="\n")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", nargs="?", default="build", choices=["build", "updates", "fetch"])
    ap.add_argument("keys", nargs="*", help="fetch: the texts to download (default: all)")
    ap.add_argument("--check", action="store_true", help="build: exit 1 if the assets are not up to date")
    args = ap.parse_args()
    try:
        if args.command == "updates":
            return cmd_updates()
        if args.command == "fetch":
            return cmd_fetch(args.keys)
        return cmd_build(args.check)
    except BuildError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
