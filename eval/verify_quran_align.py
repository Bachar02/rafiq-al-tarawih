"""Check the quran-align timings before any scoring uses them (PLAN.md §31).

Two checks, in this order, and nothing is scored unless both pass:

1. **Word mapping:** quran-align numbers Uthmani words (pause marks and the
   basmala left out); Rafiq's word stream is Simple Clean. Every ayah's words
   are mapped by letters. At least 99% of all 6,236 ayahs must map with every
   group at least half alike, or this stops.
2. **Audio:** for each recitation, against the very EveryAyah files our
   recordings were built from (the cache in eval/audio, nothing downloaded):
   the last word must end inside the file, and the first word's start and the
   last word's end must sit where speech starts and ends in the audio. At
   least 95% of the files must pass. Husary and Abdul Basit were timed on the
   64 kbps files and we use 128 and 192 kbps: this check decides whether those
   timings fit our files at all.

    py eval/verify_quran_align.py        # writes eval/data/quran-align/verification.json
"""

from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path

import numpy as np
from rafiq.asr import SAMPLE_RATE, load_audio
from rafiq.matching import get_index
from rafiq.word_truth import load_segments, map_words, word_times

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data" / "quran-align"
AUDIO = ROOT / "audio"

# Our EveryAyah folder -> the quran-align file timed on it (or on the same reciter's other bitrate).
RECITATIONS = {
    "Alafasy_128kbps": "Alafasy_128kbps",
    "Abdurrahmaan_As-Sudais_192kbps": "Abdurrahmaan_As-Sudais_192kbps",
    "Minshawy_Murattal_128kbps": "Minshawy_Murattal_128kbps",
    "Saood_ash-Shuraym_128kbps": "Saood_ash-Shuraym_128kbps",
    "Husary_128kbps": "Husary_64kbps",
    "Abdul_Basit_Murattal_192kbps": "Abdul_Basit_Murattal_64kbps",
}
MIN_MAPPED = 0.99
MIN_FILES = 0.95
ONSET_TOLERANCE = 0.25  # seconds between the first word's start and where speech starts
OFFSET_TOLERANCE = 0.6  # ...the last word's end and where speech ends (madd fades out slowly)
END_SLACK = 0.1  # the last word may end this far past the file's end (decoder padding)


def speech_bounds(audio: np.ndarray) -> tuple[float, float] | None:
    """Where speech starts and ends: 10 ms frames well above the file's quiet floor."""
    hop = SAMPLE_RATE // 100
    frames = len(audio) // hop
    if frames < 10:
        return None
    rms = np.sqrt(np.mean(audio[: frames * hop].reshape(frames, hop) ** 2, axis=1) + 1e-12)
    db = 20 * np.log10(rms)
    threshold = max(np.percentile(db, 95) - 30, np.percentile(db, 10) + 6)
    loud = db > threshold
    run = np.convolve(loud.astype(int), np.ones(3, dtype=int), mode="valid") == 3  # 30 ms in a row
    idx = np.flatnonzero(run)
    if not len(idx):
        return None
    return float(idx[0] * hop / SAMPLE_RATE), float((idx[-1] + 3) * hop / SAMPLE_RATE)


def main() -> int:
    index = get_index()
    quran = index.quran
    maps = map_words(index)
    mapped = sum(m.ok for m in maps.values())
    rate = mapped / len(maps)
    groups = [g for m in maps.values() for g in m.groups]
    split = sum(1 for us, ps in groups if len(us) != len(ps))
    print(f"1. Word mapping: {mapped} of {len(maps)} ayahs ({rate:.2%}) map with every group >= half alike")
    print(f"   {len(groups)} groups, {split} of them not one-to-one (mostly the joined vocative ya)")
    worst = sorted(m.worst for m in maps.values())
    for floor in (0.6, 0.7, 0.8):
        share = sum(w >= floor for w in worst) / len(worst)
        print(f"   ayahs whose least alike group is >= {floor:.0%} alike: {share:.2%}")
    failed = [quran.by_id(v).ref for v, m in maps.items() if not m.ok]
    if failed:
        print(f"   not mapped: {', '.join(failed[:30])}{' ...' if len(failed) > 30 else ''}")
    report: dict = {"mapping": {"ayahs": len(maps), "mapped": mapped, "rate": rate, "failed": failed}}
    if rate < MIN_MAPPED:
        print(f"STOP: mapping below {MIN_MAPPED:.0%}; nothing else is checked or scored", file=sys.stderr)
        (DATA / "verification.json").write_bytes(json.dumps(report, indent=1).encode("utf-8"))
        return 1

    print("\n2. Timings against our audio (eval/audio, the files our recordings were built from)")
    report["recitations"] = {}
    for folder, timed_on in RECITATIONS.items():
        segs = load_segments(DATA / f"{timed_on}.json")
        files = sorted((AUDIO / folder).glob("*.mp3"))
        onset_d, offset_d, passed, rows = [], [], 0, []
        for f in files:
            surah, ayah = int(f.stem[:3]), int(f.stem[3:])
            v = quran.verse(surah, ayah)
            audio = load_audio(f)
            duration = len(audio) / SAMPLE_RATE
            times = word_times(segs.get((surah, ayah), []), maps[v.id], index)
            bounds = speech_bounds(audio)
            ok = bool(times) and bounds is not None
            if ok:
                first, last = times[0][0], max(b for _, b, _ in times)
                on, off = first - bounds[0], last - bounds[1]
                onset_d.append(on)
                offset_d.append(off)
                ok = (
                    abs(on) <= ONSET_TOLERANCE
                    and abs(off) <= OFFSET_TOLERANCE
                    and last <= duration + END_SLACK
                )
            passed += ok
            detail = None
            if times and bounds is not None:
                detail = {"first_word": round(first, 3), "speech_start": round(bounds[0], 3),
                          "last_word": round(last, 3), "speech_end": round(bounds[1], 3),
                          "duration": round(duration, 3)}  # fmt: skip
            rows.append({"ayah": v.ref, "ok": ok, **(detail or {"no_timing": not times})})
        share = passed / len(files) if files else 0.0
        verdict = share >= MIN_FILES
        same = "same files" if folder == timed_on else f"timed on {timed_on}"
        med_on = statistics.median(onset_d) if onset_d else None
        med_off = statistics.median(offset_d) if offset_d else None
        print(
            f"   {folder:<32} {same:<34} {passed}/{len(files)} files pass "
            f"(first word - speech start: median {med_on if med_on is None else round(med_on, 3)} s; "
            f"last word - speech end: median {med_off if med_off is None else round(med_off, 3)} s) "
            f"-> {'TRUSTED' if verdict else 'NOT TRUSTED'}"
        )
        bad = [r["ayah"] for r in rows if not r["ok"]]
        for r in rows:
            if not r["ok"]:
                print(f"      failing {r}")
        report["recitations"][folder] = {
            "timed_on": timed_on,
            "files": len(files),
            "passed": passed,
            "trusted": verdict,
            "onset_median_s": med_on,
            "offset_median_s": med_off,
            "failing": bad,
        }
    (DATA / "verification.json").write_bytes(json.dumps(report, indent=1).encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
