"""Phase 4 experiments: smarter word highlighting from the same Whisper results (PLAN.md §32).

Evaluation only: replays the recorded laptop Whisper output (no model is run,
nothing is downloaded) through the unchanged ayah tracker and word tracker,
then tries display policies (rafiq.word_display) on top:

  baseline      the latest result's word, however old (what §30-31 measured)
  hide>X s      stale-highlight suppression
  predict ...   predictive advancement between results
  both          the two together

Every moment shown is CONFIRMED (supported by a result), PREDICTED (estimated
between results) or HIDDEN. Scored on the 22 recordings with verified exact
word times (quran-align, §31), at exactly the same moments for every policy.
Policies are chosen on 15 of them (Alafasy, Sudais, Minshawy, Shuraym) and
then reported on held-out reciters: Husary and Abdul Basit (exact truth), and
the other 18 recordings (interpolated truth, reported apart).

    py eval/word_display_bench.py                 # partials + finals and finals-only
    py eval/word_display_bench.py --json OUT.json
"""

from __future__ import annotations

import argparse
import itertools
import json
import statistics
import sys
import time
from dataclasses import fields, replace
from pathlib import Path

from rafiq.matching import Matcher, get_index
from rafiq.word_display import DisplayConfig, DisplayReport, grid, render, score_display
from rafiq.word_eval import exact_truth, replay_words, truth_points, word_truth
from rafiq.word_truth import load_segments, map_words
from verify_quran_align import RECITATIONS

EVAL = Path(__file__).resolve().parent
QURAN_ALIGN = EVAL / "data" / "quran-align"
MODES = {"partials+finals": False, "finals-only": True}
THRESHOLDS = [0.5, 0.75, 1.0, 1.5, 2.0]


def prediction_grid() -> list[DisplayConfig]:
    out = []
    for ahead, kappa, n, horizon, pause in itertools.product(
        [1, 2], [0.5, 1.0], [2, 4], [1.0, 2.0], [False, True]
    ):
        out.append(
            DisplayConfig(
                predict=True, max_ahead=ahead, kappa=kappa, min_samples=n, horizon=horizon, across_pause=pause
            )
        )
    return out


def objective(r: dict) -> float:
    """Right time, with wrong time costing twice as much (a wrong word misleads; none only fails to help)."""
    return r["useful"] - 2 * r["wrong"]


def pool(reports: list[DisplayReport]) -> dict:
    """Pool runs, weighting by recited time; medians of the per-run medians for latencies."""
    total = sum(r.scored_s for r in reports)
    out: dict = {"runs": len(reports), "minutes": total / 60}
    for f in fields(DisplayReport):
        if f.name == "scored_s":
            continue
        values = [(getattr(r, f.name), r.scored_s) for r in reports if getattr(r, f.name) is not None]
        if f.name.endswith(("median", "p90", "median_s")):
            out[f.name] = statistics.median(v for v, _ in values) if values else None
        elif f.name in ("precision", "wrong_shown"):  # shares of shown time: weight by shown time
            shown = [(getattr(r, f.name), r.scored_s * (1 - r.hidden)) for r in reports]
            w = sum(s for _, s in shown)
            out[f.name] = sum(v * s for v, s in shown) / w if w else None
        else:
            w = sum(s for _, s in values)
            out[f.name] = sum(v * s for v, s in values) / w if w else None
    return out


COLUMNS = [
    ("conf", "confirmed", ".1%"),
    ("pred", "predicted", ".1%"),
    ("hidden", "hidden", ".1%"),
    ("USEFUL", "useful", ".1%"),
    ("u.pred", "useful_predicted", ".1%"),
    ("WRONG", "wrong", ".2%"),
    ("w.pred", "wrong_predicted", ".2%"),
    ("w|shown", "wrong_shown", ".2%"),
    ("w/hour", "wrong_per_hour", ".0f"),
    ("ayah✗", "wrong_ayah", ".2%"),
    ("back/m", "backjumps_per_min", ".1f"),
    ("lat", "latency_median", ".2f"),
    ("lat90", "latency_p90", ".2f"),
    ("lat.c", "latency_confirmed_median", ".2f"),
    ("recov", "recovery_median", ".2f"),
    ("rec90", "recovery_p90", ".2f"),
    ("hid/m", "hidden_per_min", ".1f"),
    ("hid.s", "hidden_median_s", ".2f"),
]


def fmt(v, spec: str) -> str:
    return "-" if v is None else format(v, spec)


def print_table(title: str, rows: dict[str, dict]) -> None:
    width = max(30, *(len(k) for k in rows))
    print(f"\n{title}")
    print(f"  {'policy':<{width}} " + " ".join(f"{h:>7}" for h, _, _ in COLUMNS))
    for name, r in rows.items():
        print(f"  {name:<{width}} " + " ".join(f"{fmt(r[k], s):>7}" for _, k, s in COLUMNS))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--recordings", type=Path, default=EVAL / "results" / "transcripts")
    ap.add_argument("--json", type=Path, default=None)
    args = ap.parse_args()

    verified = json.loads((QURAN_ALIGN / "verification.json").read_text(encoding="utf-8"))
    if verified["mapping"]["rate"] < 0.99:
        raise SystemExit("word mapping failed verification")
    trusted = {k: v for k, v in verified["recitations"].items() if v["trusted"]}
    matcher = Matcher(get_index())
    index = matcher.index
    maps = map_words(index)
    segments = {k: load_segments(QURAN_ALIGN / f"{v['timed_on']}.json") for k, v in trusted.items()}
    recordings = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(args.recordings.glob("*.json"))]

    t0 = time.perf_counter()
    runs = []  # one per recording: truth, scored moments, replay per mode
    for rec in recordings:
        reciter = rec["reciter"]
        if reciter in trusted:
            rows = exact_truth(
                index, rec["timeline"], segments[reciter], maps, frozenset(trusted[reciter]["failing"])
            )
            group = "tune" if RECITATIONS[reciter] == reciter else "held-out exact"
        else:
            rows = word_truth(index, rec["timeline"])
            group = "held-out interpolated"
        points = grid(rows, rec, truth_points(rows, rec))
        times = [t for t, _, _ in points]
        shown = {mode: replay_words(rec, matcher, finals_only=fo) for mode, fo in MODES.items()}
        # Words are timed from the baseline's first right-ayah highlight, the same for every policy.
        first = {}
        for mode in MODES:
            frames = render(shown[mode], times, index, DisplayConfig())
            first[mode] = next(
                (t for (t, i, _), (w, _) in zip(points, frames, strict=True)
                 if w is not None and index.verse_at(w) == rows[i].verse),
                None,
            )  # fmt: skip
        runs.append({"rec": rec, "group": group, "rows": rows, "points": points, "times": times,
                     "shown": shown, "first": first})  # fmt: skip

    def evaluate(config: DisplayConfig, mode: str, which: list[dict]) -> list[DisplayReport]:
        out = []
        for run in which:
            frames = render(run["shown"][mode], run["times"], index, config)
            out.append(
                score_display(frames, run["points"], run["rows"], run["rec"], index, run["first"][mode])
            )
        return out

    groups = {
        g: [r for r in runs if r["group"] == g] for g in ("tune", "held-out exact", "held-out interpolated")
    }
    exact_runs = groups["tune"] + groups["held-out exact"]
    print("REAL recorded speech-model output (laptop, faster-whisper int8), replayed: no model run.")
    sizes = {g: len(rs) for g, rs in groups.items()}
    print(f"{len(recordings)} recordings: tune {sizes['tune']} (exact), "
          f"held-out exact {sizes['held-out exact']}, "
          f"held-out interpolated {sizes['held-out interpolated']}")  # fmt: skip

    payload: dict = {}
    for mode in MODES:
        # 1. Choose on the tuning runs.
        baseline = DisplayConfig()
        suppress = [DisplayConfig(stale_after=x) for x in THRESHOLDS]
        predicts = prediction_grid()
        tune = {c.name: pool(evaluate(c, mode, groups["tune"])) for c in [baseline, *suppress, *predicts]}
        best_hide = max(suppress, key=lambda c: objective(tune[c.name]))
        best_pred = max(predicts, key=lambda c: objective(tune[c.name]))
        combos = [replace(best_pred, stale_after=x) for x in THRESHOLDS]
        for c in combos:
            tune[c.name] = pool(evaluate(c, mode, groups["tune"]))
        best_both = max(combos, key=lambda c: objective(tune[c.name]))

        print(f"\n================ {mode} ================")
        print_table(
            f"TUNING runs ({sizes['tune']}, exact truth): baseline, every threshold, the best predictors",
            {
                "baseline": tune["baseline"],
                **{c.name: tune[c.name] for c in suppress},
                **{
                    c.name: tune[c.name] for c in sorted(predicts, key=lambda c: -objective(tune[c.name]))[:6]
                },
                **{c.name: tune[c.name] for c in combos},
            },
        )
        print(f"  chosen (useful - 2 x wrong): hide {best_hide.name} | predict {best_pred.name}")
        print(f"  chosen combination: {best_both.name}")

        chosen = {"baseline": baseline, "hide": best_hide, "predict": best_pred, "both": best_both}
        mode_out = {"tuning": tune, "chosen": {k: c.name for k, c in chosen.items()}}
        for gname in ("held-out exact", "held-out interpolated"):
            res = {f"{k}: {c.name}": pool(evaluate(c, mode, groups[gname])) for k, c in chosen.items()}
            truth = "EXACT" if "exact" in gname else "INTERPOLATED (approximate)"
            print_table(f"HELD-OUT, {gname} ({len(groups[gname])} runs, {truth} truth)", res)
            mode_out[gname] = res
        # All exact runs, by room and by reciter, for the chosen policies.
        for key, label in (("room", "room"), ("reciter", "reciter")):
            names = sorted({r["rec"][key] for r in exact_runs})
            table = {}
            for name in names:
                sub = [r for r in exact_runs if r["rec"][key] == name]
                for k in ("baseline", "both"):
                    table[f"{name[:22]} ({len(sub)}), {k}"] = pool(evaluate(chosen[k], mode, sub))
            print_table(
                f"All {len(exact_runs)} exact runs by {label}: baseline and the chosen combination", table
            )
            mode_out[f"by_{label}"] = table
        payload[mode] = mode_out

    print(f"\n(evaluated in {time.perf_counter() - t0:.0f} s)")
    print("""
  conf/pred/hidden  what the screen shows, share of recited time (adds up to 100%)
  USEFUL            a word within one of the one being recited (u.pred: of which predicted)
  WRONG             a word more than two off (w.pred: of which predicted); w|shown: share of shown time
  w/hour            separate wrong stretches per hour; ayah✗: a word outside the ayah (or the one before)
  back/m            the highlight moving back, per minute (wrong guesses undone, or real repeats)
  lat/lat90         a word starts -> it or a later word of its ayah is shown (s); lat.c: confirmed only
  recov/rec90       a stretch without a right highlight -> right again (s)
  hid/m, hid.s      stretches without a highlight per minute, and their median length (s)""")
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_bytes((json.dumps(payload, indent=1, default=str) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
