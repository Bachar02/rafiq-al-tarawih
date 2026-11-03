"""Golden files: the Python engine's outputs, for checking the Dart port against.

The app will run the engine's logic in Dart (Phase 6). Every piece that is
ported gets a golden file generated here from the Python reference, and a
Dart test that must reproduce it exactly, so the two can never drift apart.

    .venv/Scripts/python tools/golden/make_golden.py            # regenerate
    .venv/Scripts/python tools/golden/make_golden.py --check    # CI: fail if stale
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

from rafiq.normalize import normalize
from rafiq.quran import get_quran

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "mobile" / "test" / "golden"

# Real faster-whisper outputs (with diacritics, odd spellings, hallucinations).
ASR_SAMPLES = [
    "وَاللَّيْلِ إِذَا سَجَى",
    "عَمَّ يَتَسَاءَلُونَ",
    "قُلْ أَهَلُ رَبِّي بِالْإِسْطِ وَأَقِيمُوا وُجُوهَكُمْ",
    "يَا بَنِي آدَمَ خُذُوا زِينَتَكُمْ عِنْدَ كُلِّ مَسْجِدٍ وَكُنْ وَشَرَهُ",
    "وَالْمُؤْمِنِينَ",
    "الٓمٓ ذَٰلِكَ ٱلْكِتَـٰبُ",
    "Rafiq 123 — test",
    "",
    "   ",
    "فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ!؟",
]


def normalize_cases() -> list[dict]:
    q = get_quran()
    rng = random.Random(1448)
    verses = rng.sample(q.verses, 300) + [q.verse(1, 1), q.verse(2, 255), q.verse(95, 1), q.verse(97, 1)]
    inputs = []
    for v in verses:
        inputs += [v.text, v.text_uthmani]
    inputs += ASR_SAMPLES
    inputs += [s.basmala_uthmani for s in q.surahs if s.basmala_uthmani]
    seen, cases = set(), []
    for text in inputs:
        if text not in seen:
            seen.add(text)
            cases.append({"input": text, "normalized": normalize(text)})
    return cases


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    files = {"normalize.json": normalize_cases()}
    stale = []
    for name, cases in files.items():
        path = OUT / name
        text = json.dumps(cases, ensure_ascii=False, indent=0) + "\n"
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            print(f"wrote {path} ({len(cases)} cases)")
    if stale:
        print(f"stale golden files: {stale}; run tools/golden/make_golden.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
