"""Text-level benchmark: simulated ASR streams -> tracker -> product metrics.

Samples random passages from across the Quran (seeded, so runs are comparable)
and reports aggregate metrics per noise scenario. Run it before and after any
change to normalization, matching or tracking.

    py eval/text_benchmark.py              # full run
    py eval/text_benchmark.py --quick      # fewer passages, for CI
    py eval/text_benchmark.py --check      # exit 1 if below the thresholds below

Until real recordings exist (Phase 2) this is our only end-to-end signal. It is
optimistic — simulated noise is kinder than a mosque — so treat it as a floor
for regressions, not as a promise of real-world accuracy.
"""

from __future__ import annotations

import argparse
import random
import statistics
import sys
import time
from dataclasses import replace

from rafiq import evaluation
from rafiq.matching import Matcher, get_index
from rafiq.simulate import NoiseConfig, simulate
from rafiq.tracking import Tracker

SCENARIOS: dict[str, NoiseConfig] = {
    "clean": NoiseConfig.clean(),
    "light": NoiseConfig.preset("light"),
    "light+rakah": replace(NoiseConfig.preset("light"), fatiha_every=10),
    "heavy": NoiseConfig.preset("heavy"),
    "heavy+rakah": replace(NoiseConfig.preset("heavy"), fatiha_every=10),
}

# Regression floor for --check, per scenario: (min acceptable rate, max wrong jumps per 100 steps).
THRESHOLDS: dict[str, tuple[float, float]] = {
    "clean": (0.97, 0.6),
    "light": (0.96, 0.6),
    "light+rakah": (0.95, 0.6),
    "heavy": (0.95, 0.6),
    "heavy+rakah": (0.94, 0.6),
}


def passages(n: int, seed: int, total_verses: int) -> list[tuple[int, int]]:
    rng = random.Random(seed)
    out = []
    for _ in range(n):
        length = rng.randint(15, 40)
        start = rng.randint(1, total_verses - length)
        out.append((start, start + length - 1))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--passages", type=int, default=40)
    ap.add_argument("--quick", action="store_true", help="10 passages")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--check", action="store_true", help="fail if below regression thresholds")
    args = ap.parse_args()

    index = get_index()
    tracker = Tracker(Matcher(index))
    sample = passages(10 if args.quick else args.passages, args.seed, len(index.quran))

    print(f"{'scenario':<13} {'steps':>6} {'exact':>6} {'accept':>7} {'jumps/100':>10} "
          f"{'recover':>8} {'ms/step':>8}")  # fmt: skip
    failed = []
    for name, noise in SCENARIOS.items():
        reports, elapsed, steps_total = [], 0.0, 0
        for i, (a, b) in enumerate(sample):
            steps = simulate(index, a, b, noise, seed=args.seed + i)
            t = time.perf_counter()
            _, report = evaluation.run(tracker, steps)
            elapsed += time.perf_counter() - t
            steps_total += len(steps)
            reports.append(report)

        def weighted(attr: str, reports=reports) -> float:
            return sum(getattr(r, attr) * r.steps for r in reports) / sum(r.steps for r in reports)

        exact, accept = weighted("accuracy"), weighted("acceptable")
        jumps = 100 * sum(r.wrong_jumps for r in reports) / steps_total
        recoveries = [r.mean_recovery for r in reports if r.mean_recovery]
        recovery = statistics.fmean(recoveries) if recoveries else 0.0
        ms = 1000 * elapsed / steps_total
        print(f"{name:<13} {steps_total:>6} {exact:>6.3f} {accept:>7.3f} {jumps:>10.2f} ", end="")
        print(f"{recovery:>8.2f} {ms:>8.1f}")

        min_accept, max_jumps = THRESHOLDS[name]
        if accept < min_accept or jumps > max_jumps:
            failed.append(
                f"{name}: accept {accept:.3f} (min {min_accept}), jumps/100 {jumps:.2f} (max {max_jumps})"
            )

    if args.check and failed:
        print("\nREGRESSION:\n  " + "\n  ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
