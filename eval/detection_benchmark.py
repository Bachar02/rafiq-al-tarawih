"""Detection benchmark: the app opens mid-recitation knowing nothing.

Each trial picks a random place anywhere in the Quran, joins partway into an
ayah, and measures how quickly the tracker finds the right surah *and* ayah on
its own. The optional user hint (surah or juz) is measured separately, including
a deliberately *wrong* hint, which must never be much worse than no hint.

    py eval/detection_benchmark.py            # 300 trials per row
    py eval/detection_benchmark.py --quick    # 80 trials, for CI
    py eval/detection_benchmark.py --check    # exit 1 if below the thresholds

Seconds are an estimate: chunks average ~5.5 words and imams recite roughly
2 words per second in Taraweeh, so one chunk is about 2.75 s of audio.
"""

from __future__ import annotations

import argparse
import random
import statistics
import sys
from dataclasses import dataclass

from rafiq import evaluation
from rafiq.matching import Matcher, get_index
from rafiq.simulate import NoiseConfig, simulate
from rafiq.tracking import Tracker

SECONDS_PER_CHUNK = 2.75
HINTS = ("none", "surah", "juz", "wrong surah")

# Regression floor for --check, per (noise, hint): (min locked within 3 chunks, max first-shown-wrong).
THRESHOLDS: dict[tuple[str, str], tuple[float, float]] = {
    ("light", "none"): (0.95, 0.03),
    ("light", "surah"): (0.97, 0.03),
    ("heavy", "none"): (0.92, 0.04),
    ("heavy", "surah"): (0.95, 0.04),
}


@dataclass
class Trial:
    start: int
    end: int
    skip: int
    seed: int


def trials(n: int, seed: int, total: int) -> list[Trial]:
    rng = random.Random(seed)
    out = []
    for i in range(n):
        start = rng.randint(1, total - 12)
        out.append(Trial(start, start + 11, rng.randint(0, 6), seed + i))
    return out


def hint_range(q, verse_id: int, mode: str, rng: random.Random) -> tuple[int, int] | None:
    v = q.by_id(verse_id)
    if mode == "surah":
        s = q.surah(v.surah)
        return s.first_verse_id, s.last_verse_id
    if mode == "juz":
        return q.juz_span(q.juz_of(verse_id))
    if mode == "wrong surah":
        other = rng.choice([s for s in q.surahs if s.index not in (v.surah, 1)])
        return other.first_verse_id, other.last_verse_id
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--trials", type=int, default=300)
    ap.add_argument("--quick", action="store_true", help="80 trials")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--check", action="store_true", help="fail if below regression thresholds")
    args = ap.parse_args()

    index = get_index()
    q = index.quran
    tracker = Tracker(Matcher(index))
    sample = trials(80 if args.quick else args.trials, args.seed, len(q))

    print(f"{'noise':<6} {'hint':<12} {'<=1':>6} {'<=2':>6} {'<=3':>6} {'<=5':>6} {'median':>7} "
          f"{'~sec':>5} {'never':>6} {'1st wrong':>9}")  # fmt: skip
    failed = []
    for noise_name in ("light", "heavy"):
        noise = NoiseConfig.preset(noise_name)
        for mode in HINTS:
            rng = random.Random(args.seed)
            locks: list[int | None] = []
            first_wrong = 0
            for t in sample:
                steps = simulate(index, t.start, t.end, noise, seed=t.seed, skip_words=t.skip)
                tracker.hint(*(hint_range(q, t.start, mode, rng) or (None,)))
                _, report = evaluation.run(tracker, steps)
                locks.append(report.time_to_lock)
                first_wrong += report.first_shown_wrong
            tracker.hint(None)

            n = len(locks)
            within = {k: sum(1 for x in locks if x is not None and x <= k) / n for k in (1, 2, 3, 5)}
            found = [x for x in locks if x is not None]
            median = statistics.median(found) if found else float("nan")
            never = sum(x is None for x in locks) / n
            wrong = first_wrong / n
            print(f"{noise_name:<6} {mode:<12} {within[1]:>6.0%} {within[2]:>6.0%} {within[3]:>6.0%} "
                  f"{within[5]:>6.0%} {median:>7.1f} {median * SECONDS_PER_CHUNK:>5.0f} {never:>6.1%} "
                  f"{wrong:>9.1%}")  # fmt: skip

            limits = THRESHOLDS.get((noise_name, mode))
            if limits and (within[3] < limits[0] or wrong > limits[1]):
                failed.append(f"{noise_name}/{mode}: <=3 chunks {within[3]:.0%} (min {limits[0]:.0%}), "
                              f"first wrong {wrong:.1%} (max {limits[1]:.0%})")  # fmt: skip

    if args.check and failed:
        print("\nREGRESSION:\n  " + "\n  ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
