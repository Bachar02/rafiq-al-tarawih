"""Summarise the QuranView benchmark and apply the R2 budgets (PLAN.md §18).

Run after:
    flutter drive --profile -d <device> --driver=test_driver/perf_driver.dart \
        --target=integration_test/quran_view_perf_test.dart

    py tool/perf_report.py [--dir build] [--markdown]

Budgets, for a 60 Hz phone (16.7 ms per frame):
  scrolling (long surah, juz 30, Taraweeh follow):
      90th percentile frame build <= 16 ms and raster <= 16 ms,
      99th percentile frame build <= 33 ms (never more than one dropped frame there),
      at most 5% of frames over budget (build or raster).
  navigation jumps: 90th percentile wall time <= 250 ms (a jump is a cut;
      a quarter of a second still reads as instant).
Exit status 1 if any budget fails.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCROLL_PREFIXES = ("baqarah_", "juz30_", "follow_")


def load(directory: Path) -> tuple[dict[str, dict], dict]:
    summaries = {
        p.name.removesuffix(".timeline_summary.json"): json.loads(p.read_text(encoding="utf-8"))
        for p in sorted(directory.glob("*.timeline_summary.json"))
    }
    extra_path = directory / "perf_extra.json"
    extra = json.loads(extra_path.read_text(encoding="utf-8")) if extra_path.exists() else {}
    return summaries, extra


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return float("nan")
    k = min(len(ordered) - 1, max(0, round(p / 100 * (len(ordered) - 1))))
    return ordered[k]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", type=Path, default=Path(__file__).resolve().parents[1] / "build")
    ap.add_argument("--markdown", action="store_true", help="print a Markdown table for PLAN.md")
    args = ap.parse_args()

    summaries, extra = load(args.dir)
    if not summaries:
        print(f"no *.timeline_summary.json in {args.dir}; run the benchmark first", file=sys.stderr)
        return 1

    failures: list[str] = []
    rows = []
    for name, s in summaries.items():
        if not name.startswith(SCROLL_PREFIXES + ("jumps_",)):
            continue
        frames = max(1, s.get("frame_count", 0))
        build90 = s.get("90th_percentile_frame_build_time_millis", float("nan"))
        build99 = s.get("99th_percentile_frame_build_time_millis", float("nan"))
        raster90 = s.get("90th_percentile_frame_rasterizer_time_millis", float("nan"))
        worst = s.get("worst_frame_build_time_millis", float("nan"))
        missed = s.get("missed_frame_build_budget_count", 0)
        missed += s.get("missed_frame_rasterizer_budget_count", 0)
        missed_pct = 100 * missed / frames
        rows.append((name, frames, build90, build99, worst, raster90, missed_pct))
        if name.startswith(SCROLL_PREFIXES):
            if build90 > 16:
                failures.append(f"{name}: 90th percentile build {build90:.1f} ms > 16")
            if raster90 > 16:
                failures.append(f"{name}: 90th percentile raster {raster90:.1f} ms > 16")
            if build99 > 33:
                failures.append(f"{name}: 99th percentile build {build99:.1f} ms > 33")
            if missed_pct > 5:
                failures.append(f"{name}: {missed_pct:.1f}% of frames over budget > 5%")

    jump_rows = []
    for key, values in sorted(extra.items()):
        if key.startswith("jump_wall_ms_") and values:
            p50, p90, worst = percentile(values, 50), percentile(values, 90), max(values)
            jump_rows.append((key.removeprefix("jump_wall_ms_"), p50, p90, worst))
            if p90 > 250:
                failures.append(f"jumps {key}: 90th percentile {p90:.0f} ms > 250")

    if args.markdown:
        print("| Scenario | Frames | Build p90 | Build p99 | Build worst | Raster p90 | Over budget |")
        print("|---|---|---|---|---|---|---|")
        for name, frames, b90, b99, worst, r90, missed in rows:
            print(
                f"| {name} | {frames} | {b90:.1f} ms | {b99:.1f} ms | {worst:.1f} ms "
                f"| {r90:.1f} ms | {missed:.1f}% |"
            )
        if jump_rows:
            print()
            print("| Jumps | Median | p90 | Worst |")
            print("|---|---|---|---|")
            for tag, p50, p90, worst in jump_rows:
                print(f"| {tag} | {p50:.0f} ms | {p90:.0f} ms | {worst:.0f} ms |")
    else:
        print(f"{'scenario':<16}{'frames':>7}{'b p90':>8}{'b p99':>8}{'b worst':>9}{'r p90':>8}{'over':>7}")
        for name, frames, b90, b99, worst, r90, missed in rows:
            print(f"{name:<16}{frames:>7}{b90:>8.1f}{b99:>8.1f}{worst:>9.1f}{r90:>8.1f}{missed:>6.1f}%")
        for tag, p50, p90, worst in jump_rows:
            print(f"jumps {tag:<10} wall ms: median {p50:.0f}, p90 {p90:.0f}, worst {worst:.0f}")

    print()
    if failures:
        print("FAIL")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("PASS: every scenario within budget")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
