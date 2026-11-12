"""The word tracker on REAL recorded Whisper output (PLAN.md §30).

Replays recordings of what the speech model actually produced (no model is
run, nothing is downloaded) through the existing ayah tracker, unchanged, and
the word tracker anchored from it, in two modes:

  partials+finals  every result, as a phone fast enough for live previews runs
  finals-only      only the transcript at each pause, as a slow phone runs (§27)

Sources are reported separately, never pooled:

  py eval/word_replay.py eval/results/transcripts      # laptop: faster-whisper int8 (CTranslate2)
  py eval/word_replay.py path/to/results.json          # phone: integration_test/ondevice_test.dart

Ayah-level numbers are EXACT (the stream's ayah timeline). Word-level numbers
are APPROXIMATE: each ayah's time is shared out among its words by letter
count, as no word timings exist for these recordings.

The simulated benchmark (eval/word_benchmark.py) measures something else and
is not mixed in here.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

from rafiq.matching import Matcher, get_index
from rafiq.word_eval import RealWordReport, replay_words, score_words

MODES = {"partials+finals": False, "finals-only": True}


def load(path: Path) -> tuple[str, list[dict]]:
    """Recordings and a description of where they come from."""
    if path.is_dir():
        recs = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(path.glob("*.json"))]
        return (
            f"laptop recordings in {path} (eval/audio_bench.py --record): Rafiq's server model, "
            "faster-whisper int8 (CTranslate2), device not recorded",
            recs,
        )
    report = json.loads(path.read_text(encoding="utf-8"))
    recs = [s for s in report.get("streams", []) if "events" in s]
    if not recs:
        raise SystemExit(f"{path}: no recorded events (made before the device test recorded them?)")
    return f"phone, {report.get('device', '?')}: model {report.get('model', '?')} (sherpa-onnx int8)", recs


def _mean(reports: list[RealWordReport], attr: str, weight: str = "recited_s") -> float | None:
    pairs = [(getattr(r, attr), getattr(r, weight)) for r in reports if getattr(r, attr) is not None]
    total = sum(w for _, w in pairs)
    return sum(v * w for v, w in pairs) / total if total else None


def _median(reports: list[RealWordReport], attr: str) -> float | None:
    values = [getattr(r, attr) for r in reports if getattr(r, attr) is not None]
    return statistics.median(values) if values else None


def _f(x: float | None, spec: str) -> str:
    return "-" if x is None else format(x, spec)


def summarize(reports: list[RealWordReport]) -> dict:
    recited = sum(r.recited_s for r in reports)
    lit = sum(r.coverage * r.recited_s for r in reports)

    def over_lit(attr: str) -> float | None:
        return sum(getattr(r, attr) * r.coverage * r.recited_s for r in reports) / lit if lit else None

    wrong_stretches = sum(r.ayah_wrong_per_hour * r.recited_s / 3600 for r in reports)
    return {
        "runs": len(reports),
        "recited_min": recited / 60,
        "coverage": lit / recited if recited else 0.0,
        "first_s": _median(reports, "first_s"),
        "ayah_same": over_lit("ayah_same"),
        "ayah_wrong": over_lit("ayah_wrong"),
        "ayah_wrong_per_hour": wrong_stretches / (recited / 3600) if recited else 0.0,
        "ayah_shown_same": _mean(reports, "ayah_shown_same"),
        "word_near": over_lit("word_near"),
        "word_wrong": over_lit("word_wrong"),
        "useful": _mean(reports, "useful"),
        "aligned": _mean(reports, "aligned", weight="events"),
        "word_delay_median": _median(reports, "word_delay_median"),
        "word_delay_p90": _median(reports, "word_delay_p90"),
        "words_reached": _mean(reports, "words_reached"),
        "recovery_median": _median(reports, "recovery_median"),
        "recovery_p90": _median(reports, "recovery_p90"),
        "events": sum(r.events for r in reports),
        "asr_ms_median": _median(reports, "asr_ms_median"),
        "asr_ms_p90": _median(reports, "asr_ms_p90"),
        "age_median": _median(reports, "age_median"),
        "age_p90": _median(reports, "age_p90"),
    }


# (label, key, format): metrics as rows, one column per mode or room.
ROWS = [
    ("runs", "runs", "d"),
    ("recited minutes", "recited_min", ".1f"),
    ("word highlighted (share of recited time)", "coverage", ".1%"),
    ("first right-ayah highlight (s, median)", "first_s", ".1f"),
    ("EXACT, ayah timeline (over highlighted time)", None, None),
    ("  word in the ayah being recited", "ayah_same", ".1%"),
    ("  word in a wrong ayah (not that one, nor the one before)", "ayah_wrong", ".2%"),
    ("  wrong-ayah stretches per hour", "ayah_wrong_per_hour", ".1f"),
    ("  ayah tracker's ayah right (all recited time)", "ayah_shown_same", ".1%"),
    ("APPROXIMATE, word times by letter count", None, None),
    ("  within one word (over highlighted time)", "word_near", ".1%"),
    ("  more than two words off (over highlighted time)", "word_wrong", ".2%"),
    ("  useful: highlighted and within one word (all time)", "useful", ".1%"),
    ("  aligned: within one word of the audio covered", "aligned", ".1%"),
    ("  word start -> highlighted (s, median)", "word_delay_median", ".2f"),
    ("  word start -> highlighted (s, p90)", "word_delay_p90", ".2f"),
    ("  words highlighted before their ayah ends", "words_reached", ".1%"),
    ("  recovery to a right highlight (s, median)", "recovery_median", ".2f"),
    ("  recovery to a right highlight (s, p90)", "recovery_p90", ".2f"),
    ("SPEECH MODEL, as recorded", None, None),
    ("  results used", "events", "d"),
    ("  transcription per result (ms, median)", "asr_ms_median", ".0f"),
    ("  transcription per result (ms, p90)", "asr_ms_p90", ".0f"),
    ("  audio end -> result ready (s, median)", "age_median", ".2f"),
    ("  audio end -> result ready (s, p90)", "age_p90", ".2f"),
]


def print_block(title: str, columns: dict[str, dict]) -> None:
    width = max(14, *(len(c) for c in columns))
    print(f"\n{title}")
    print(f"  {'':<58}" + "".join(f"{c:>{width + 2}}" for c in columns))
    for label, key, spec in ROWS:
        if key is None:
            print(f"  {label}")
            continue
        print(f"  {label:<58}" + "".join(f"{_f(s[key], spec):>{width + 2}}" for s in columns.values()))


NOTES = """
  Finals-only reuses the timings recorded with partials running, so its result times are slightly
  pessimistic. A highlight that stays on the last word heard while the imam goes on counts as shown but
  not as useful: compare "useful", not "word highlighted", across modes.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", type=Path, help="a directory of recordings, or a phone results.json")
    ap.add_argument("--by-room", action="store_true", help="also break down by room")
    ap.add_argument("--json", type=Path, default=None, help="save the summaries here")
    args = ap.parse_args()

    description, recordings = load(args.source)
    matcher = Matcher(get_index())
    index = matcher.index
    t0 = time.perf_counter()
    reports: dict[str, list[tuple[dict, RealWordReport]]] = {m: [] for m in MODES}
    for rec in recordings:
        for mode, finals_only in MODES.items():
            shown = replay_words(rec, matcher, finals_only=finals_only)
            reports[mode].append((rec, score_words(shown, rec, index, finals_only=finals_only)))

    print(f"REAL recorded speech-model output, replayed (no model run): {description}")
    print(f"{len(recordings)} runs, replayed in {time.perf_counter() - t0:.0f} s")
    summary = {mode: summarize([r for _, r in rs]) for mode, rs in reports.items()}
    print_block("All runs", summary)
    by_room: dict[str, dict] = {}
    if args.by_room:
        rooms = sorted({rec.get("room", "?") for rec in recordings})
        for mode, rs in reports.items():
            for room in rooms:
                by_room[f"{mode}, {room}"] = summarize([r for rec, r in rs if rec.get("room", "?") == room])
        for mode in MODES:
            columns = {k.split(", ")[1]: v for k, v in by_room.items() if k.startswith(mode)}
            print_block(f"By room, {mode}", columns)
    print(NOTES)
    if args.json:
        payload = {"source": description, "all": summary, "by_room": by_room}
        args.json.write_bytes((json.dumps(payload, indent=1) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
