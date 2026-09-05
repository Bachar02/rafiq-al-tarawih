"""Derive data/quran.json from the verbatim Tanzil sources in data/raw/.

The text file and the metadata XML are independent publications. Cross-checking
them against each other is the whole point of this script: a corrupted or
truncated Quran would not announce itself later, it would just quietly degrade
matching accuracy in ways that look like a modelling problem. So every
disagreement between the two sources aborts the build.

Usage:  py data/build_quran.py [-o data/quran.json]
"""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent
TEXT_SRC = DATA_DIR / "raw" / "quran-simple-clean.txt"
META_SRC = DATA_DIR / "raw" / "quran-data.xml"
DEFAULT_OUT = DATA_DIR / "quran.json"

TOTAL_VERSES = 6236
TOTAL_SURAHS = 114

SOURCE_NOTE = (
    "Tanzil Quran Text (Simple Clean, v1.1) + Tanzil metadata, https://tanzil.net"
)
LICENSE_NOTE = "Creative Commons Attribution 3.0 — Copyright (C) Tanzil Project"


class BuildError(Exception):
    """A source-data inconsistency. Always fatal; never worked around."""


def parse_text(path: Path) -> list[dict]:
    """Parse `surah|ayah|text` lines, skipping blanks and the copyright block."""
    verses: list[dict] = []
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != 3:
            raise BuildError(
                f"{path.name}:{lineno}: expected 3 |-separated fields, got {len(parts)}"
            )
        surah_s, ayah_s, text = parts
        try:
            surah, ayah = int(surah_s), int(ayah_s)
        except ValueError:
            raise BuildError(
                f"{path.name}:{lineno}: non-integer surah/ayah {surah_s!r}/{ayah_s!r}"
            ) from None
        text = text.strip()
        if not text:
            raise BuildError(
                f"{path.name}:{lineno}: empty verse text for {surah}:{ayah}"
            )
        verses.append(
            {"id": len(verses) + 1, "surah": surah, "ayah": ayah, "text": text}
        )
    return verses


def parse_metadata(path: Path) -> dict:
    root = ET.parse(path).getroot()

    surahs = []
    for el in root.findall("./suras/sura"):
        surahs.append(
            {
                "index": int(el.get("index")),
                "name_ar": el.get("name"),
                "name_translit": el.get("tname"),
                "name_en": el.get("ename"),
                "ayah_count": int(el.get("ayas")),
                "revelation_type": el.get("type"),
                "revelation_order": int(el.get("order")),
                "rukus": int(el.get("rukus")),
                # `start` is Tanzil's 0-based global offset; converted to our
                # 1-based verse id after it has been validated against the text.
                "_start": int(el.get("start")),
            }
        )

    juzs = [
        {
            "index": int(el.get("index")),
            "surah": int(el.get("sura")),
            "ayah": int(el.get("aya")),
        }
        for el in root.findall("./juzs/juz")
    ]
    sajdas = [
        {
            "index": int(el.get("index")),
            "surah": int(el.get("sura")),
            "ayah": int(el.get("aya")),
            "type": el.get("type"),
        }
        for el in root.findall("./sajdas/sajda")
    ]
    return {"surahs": surahs, "juzs": juzs, "sajdas": sajdas}


def validate(verses: list[dict], meta: dict) -> None:
    surahs = meta["surahs"]

    if len(verses) != TOTAL_VERSES:
        raise BuildError(f"text has {len(verses)} verses, expected {TOTAL_VERSES}")
    if len(surahs) != TOTAL_SURAHS:
        raise BuildError(f"metadata has {len(surahs)} surahs, expected {TOTAL_SURAHS}")

    if [s["index"] for s in surahs] != list(range(1, TOTAL_SURAHS + 1)):
        raise BuildError("metadata surah indices are not 1..114 in order")

    declared_total = sum(s["ayah_count"] for s in surahs)
    if declared_total != TOTAL_VERSES:
        raise BuildError(
            f"metadata ayah counts sum to {declared_total}, expected {TOTAL_VERSES}"
        )

    # Walk the text once, checking surah order, ayah contiguity, and that each
    # surah's length matches what the metadata independently declares.
    expected = {s["index"]: s["ayah_count"] for s in surahs}
    seen: dict[int, int] = {}
    prev_surah = 0
    for v in verses:
        s, a = v["surah"], v["ayah"]
        if s == prev_surah:
            if a != seen[s] + 1:
                raise BuildError(
                    f"surah {s}: ayah {a} follows {seen[s]}, expected {seen[s] + 1}"
                )
        elif s == prev_surah + 1:
            if a != 1:
                raise BuildError(f"surah {s} starts at ayah {a}, expected 1")
            seen[s] = 0
        else:
            raise BuildError(f"surah order jumps from {prev_surah} to {s}")
        seen[s] = a
        prev_surah = s

    for index, count in expected.items():
        if seen.get(index) != count:
            raise BuildError(
                f"surah {index}: text has {seen.get(index)} ayahs, metadata declares {count}"
            )

    # Tanzil's per-surah `start` offset is a third, redundant encoding of the
    # same layout. If it disagrees, one of the two files is not what we think.
    running = 0
    for s in surahs:
        if s["_start"] != running:
            raise BuildError(
                f"surah {s['index']}: metadata start={s['_start']}, computed {running}"
            )
        running += s["ayah_count"]

    valid = {(v["surah"], v["ayah"]) for v in verses}
    for name, marks in (("juz", meta["juzs"]), ("sajda", meta["sajdas"])):
        for m in marks:
            if (m["surah"], m["ayah"]) not in valid:
                raise BuildError(
                    f"{name} {m['index']} points at nonexistent verse {m['surah']}:{m['ayah']}"
                )


def build(text_src: Path, meta_src: Path) -> dict:
    for p in (text_src, meta_src):
        if not p.exists():
            raise BuildError(f"missing source file: {p}")

    verses = parse_text(text_src)
    meta = parse_metadata(meta_src)
    validate(verses, meta)

    surahs = []
    for s in meta["surahs"]:
        s = dict(s)
        s["first_verse_id"] = s.pop("_start") + 1  # 0-based offset -> 1-based id
        surahs.append(s)

    return {
        "meta": {
            "source": SOURCE_NOTE,
            "license": LICENSE_NOTE,
            "text_variant": "simple-clean",
            "note": "Derived artifact. Do not edit by hand; rebuild with data/build_quran.py.",
            "verse_count": len(verses),
            "surah_count": len(surahs),
        },
        "surahs": surahs,
        "verses": verses,
        "juzs": meta["juzs"],
        "sajdas": meta["sajdas"],
    }


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "-o",
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help="output path (default: data/quran.json)",
    )
    args = ap.parse_args()

    try:
        payload = build(TEXT_SRC, META_SRC)
    except BuildError as e:
        print(f"build failed: {e}", file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    size_mb = args.out.stat().st_size / 1e6
    print(
        f"wrote {args.out} "
        f"({payload['meta']['verse_count']} verses, {payload['meta']['surah_count']} surahs, "
        f"{len(payload['juzs'])} juzs, {len(payload['sajdas'])} sajdas, {size_mb:.2f} MB)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
