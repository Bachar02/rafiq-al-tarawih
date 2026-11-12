"""Word-level benchmark: simulated CTC letter streams -> word tracker -> metrics.

The word tracker (`rafiq.words`) is measured here before any streaming speech
model exists (PLAN.md §29). Seeded random passages from across the Quran are
recited letter by letter (`rafiq.word_sim`) under four noise levels, with and
without al-Fatiha every few ayahs, and the tracker is anchored as the ayah
tracker would anchor it (late, at the start, after each far jump, and when it
says it is lost).

    py eval/word_benchmark.py              # full run
    py eval/word_benchmark.py --quick      # fewer passages, for CI
    py eval/word_benchmark.py --check      # exit 1 if below the thresholds below

Columns, over the letters recited after the first anchor:
  shown  a word is highlighted;  exact / near  it is the word, or within one;
  wrong  it is more than two words off (what must not happen);
  lag    words behind;  found  recited words highlighted while being recited.

Simulated letters are kinder and more regular than a real model's output, so
these numbers catch regressions; they do not promise real-world accuracy.
"""

from __future__ import annotations

import argparse
import random
import statistics
import sys
import time
from dataclasses import replace

from rafiq.matching import get_index
from rafiq.word_sim import LetterNoise, WordReport, run, simulate_letters
from rafiq.words import WordTracker

SCENARIOS: dict[str, LetterNoise] = {
    "clean": LetterNoise.preset("clean"),
    "light": LetterNoise.preset("light"),
    "light+rakah": replace(LetterNoise.preset("light"), fatiha_every=6),
    "heavy": LetterNoise.preset("heavy"),
    "heavy+rakah": replace(LetterNoise.preset("heavy"), fatiha_every=6),
    "broken": LetterNoise.preset("broken"),
}

# Regression floor for --check: (min shown, min near, max wrong). "broken" is
# a model that hears little: it must stay quiet rather than show wrong words.
THRESHOLDS: dict[str, tuple[float, float, float]] = {
    "clean": (0.90, 0.98, 0.005),
    "light": (0.75, 0.97, 0.010),
    "light+rakah": (0.60, 0.96, 0.012),
    "heavy": (0.50, 0.96, 0.010),
    "heavy+rakah": (0.40, 0.95, 0.012),
    "broken": (0.0, 0.0, 0.015),
}


def passages(n: int, seed: int, total_verses: int) -> list[tuple[int, int]]:
    rng = random.Random(seed)
    out = []
    for _ in range(n):
        length = rng.randint(8, 16)
        start = rng.randint(8, total_verses - length)
        out.append((start, start + length - 1))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--passages", type=int, default=30)
    ap.add_argument("--quick", action="store_true", help="8 passages")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--check", action="store_true", help="fail if below regression thresholds")
    args = ap.parse_args()

    index = get_index()
    tracker = WordTracker(index)
    sample = passages(8 if args.quick else args.passages, args.seed, len(index.quran))

    print(f"{'scenario':<12} {'letters':>8} {'shown':>6} {'exact':>6} {'near':>6} {'wrong':>7} "
          f"{'lag':>5} {'found':>6} {'anchors':>8} {'us/letter':>10}")  # fmt: skip
    failed = []
    for name, noise in SCENARIOS.items():
        reports: list[WordReport] = []
        elapsed, fed = 0.0, 0
        for i, (a, b) in enumerate(sample):
            letters = simulate_letters(index, a, b, noise, seed=args.seed + i)
            t = time.perf_counter()
            _, report = run(tracker, letters)
            elapsed += time.perf_counter() - t
            fed += len(letters)
            reports.append(report)

        letters_total = sum(r.letters for r in reports)
        shown_total = sum(r.shown * r.letters for r in reports)

        def over_shown(attr: str, reports=reports, shown_total=shown_total) -> float:
            if not shown_total:
                return 0.0
            return sum(getattr(r, attr) * r.shown * r.letters for r in reports) / shown_total

        shown = shown_total / letters_total
        exact, near, wrong, lag = (over_shown(a) for a in ("exact", "near", "wrong", "lag"))
        found = statistics.fmean(r.found for r in reports)
        anchors = statistics.fmean(r.anchors for r in reports)
        print(f"{name:<12} {letters_total:>8} {shown:>6.3f} {exact:>6.3f} {near:>6.3f} {wrong:>7.4f} "
              f"{lag:>5.2f} {found:>6.3f} {anchors:>8.1f} {1e6 * elapsed / fed:>10.0f}")  # fmt: skip

        min_shown, min_near, max_wrong = THRESHOLDS[name]
        if shown < min_shown or near < min_near or wrong > max_wrong:
            failed.append(
                f"{name}: shown {shown:.3f} (min {min_shown}), near {near:.3f} (min {min_near}), "
                f"wrong {wrong:.4f} (max {max_wrong})"
            )

    if args.check and failed:
        print("\nREGRESSION:\n  " + "\n  ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
