"""Multi-reciter audio benchmark: the regression suite for the whole live pipeline.

Every run streams a real recitation through the same Listener the server uses,
on a simulated real-time clock (so lag is what a user would see on this
machine), joins a few seconds late, and is told nothing. Passages are random
but seeded, start anywhere in the Quran, may cross into the next surah (with
the reciter's basmala, as imams do), and are the same for every reciter so
reciters are directly comparable.

    py eval/audio_bench.py --quick                     # 6 reciters x 2 passages x 2 rooms (~25 min CPU)
    py eval/audio_bench.py                             # 12 reciters x 3 passages x 3 rooms
    py eval/audio_bench.py --save eval/results/x.json  # keep the numbers
    py eval/audio_bench.py --baseline eval/results/baseline.json --check

`--check` fails on the accuracy and stability thresholds below. Lag is
reported but not gated: it depends on the machine (CPU vs GPU, on battery or
not). Rooms: "clean" (studio), "mosque" (moderate hall, listener mid-room),
"far" (big echoing hall, at the back: a stress test, reported only).
"""

from __future__ import annotations

import argparse
import json
import random
import statistics
import subprocess
import sys
import time
from dataclasses import asdict
from pathlib import Path

from audiolib import Room, RunResult, build_stream, degrade, replay_realtime, score_run
from rafiq.asr import SAMPLE_RATE, EnergyVad, Listener, Segmenter, WhisperTranscriber
from rafiq.matching import Matcher, get_index
from rafiq.tracking import Tracker

RECITERS = [
    "Alafasy_128kbps",  # modern, moderate tempo
    "Husary_128kbps",  # slow, precise tajweed
    "Abdurrahmaan_As-Sudais_192kbps",  # fast, Haram imam
    "Minshawy_Murattal_128kbps",  # classic Egyptian murattal
    "Saood_ash-Shuraym_128kbps",  # fast, Haram imam
    "MaherAlMuaiqly128kbps",  # Haram imam
    "Abdul_Basit_Murattal_192kbps",  # melodic, long madd
    "Ghamadi_40kbps",  # low bitrate recording
    "Hudhaify_128kbps",  # Masjid an-Nabawi imam
    "Yasser_Ad-Dussary_128kbps",  # popular Taraweeh imam
    "Nasser_Alqatami_128kbps",  # Taraweeh style
    "Muhammad_Ayyoub_128kbps",  # Masjid an-Nabawi, measured pace
]
ROOMS = {
    "clean": Room(),
    "mosque": Room(rt60=1.5, drr_db=3, snr_db=20),
    "far": Room(rt60=2.0, drr_db=0, snr_db=15),
}
# Regression floor for --check, per room: (min acceptable, max wrong jumps per hour, min detected fraction).
THRESHOLDS = {
    "clean": (0.85, 6.0, 0.95),
    "mosque": (0.75, 6.0, 0.90),
}


def passages(q, index, n: int, seed: int, words: int = 60, max_ayahs: int = 15) -> list[list[int]]:
    """`n` seeded passages of ~`words` words, each a list of verse ids (1:1 = a basmala)."""
    rng = random.Random(seed)
    out = []
    while len(out) < n:
        start = rng.randint(8, len(q) - max_ayahs)  # not inside al-Fatiha itself
        verses, count = [], 0
        for vid in range(start, start + max_ayahs):
            v = q.by_id(vid)
            if v.ayah == 1 and q.surah(v.surah).has_basmala:
                verses.append(1)  # the imam recites the basmala before a new surah
            verses.append(vid)
            a, b = index.verse_span(vid)
            count += b - a
            if count >= words:
                break
        out.append(verses)
    return out


def run_one(transcriber, index, audio, timeline, join: float) -> RunResult:
    listener = Listener(Segmenter(EnergyVad()), transcriber, Tracker(Matcher(index)))
    clip = audio[int(join * SAMPLE_RATE) :]
    heard, ready = replay_realtime(listener, clip)
    return score_run(heard, ready, timeline, join, len(clip) / SAMPLE_RATE)


def summarize(runs: list[dict], key: str) -> dict[str, dict]:
    groups: dict[str, list[dict]] = {}
    for r in runs:
        groups.setdefault(r[key], []).append(r)
    out = {}
    for name, rs in groups.items():
        finals = sum(r["finals"] for r in rs) or 1
        hours = sum(r["seconds"] for r in rs) / 3600
        lags = [r["lag_median"] for r in rs if r["lag_median"] is not None]
        p90s = [r["lag_p90"] for r in rs if r["lag_p90"] is not None]
        detects = [r["detect_s"] for r in rs if r["detect_s"] is not None]
        out[name] = {
            "runs": len(rs),
            "acceptable": round(sum(r["acceptable"] * r["finals"] for r in rs) / finals, 3),
            "wrong_per_hour": round(sum(r["wrong_jumps"] for r in rs) / hours, 1) if hours else 0.0,
            "detected": round(len(detects) / len(rs), 3),
            "detect_s": round(statistics.median(detects), 1) if detects else None,
            "lag_median": round(statistics.median(lags), 2) if lags else None,
            "lag_p90": round(max(p90s), 2) if p90s else None,
            "never_shown": sum(r["never_shown"] for r in rs),
            "asr_load": round(statistics.fmean(r["asr_load"] for r in rs), 2),
        }
    return out


def print_table(title: str, table: dict[str, dict], baseline: dict[str, dict] | None = None) -> None:
    print(f"\n{title}")
    print(f"  {'':<32} {'runs':>4} {'right':>6} {'wrong/h':>8} {'found':>6} {'detect':>7} "
          f"{'lag':>5} {'lag90':>6} {'missed':>6} {'load':>5}")  # fmt: skip
    for name, s in table.items():

        def fmt(v, spec, suffix=""):
            return "–" if v is None else f"{v:{spec}}{suffix}"

        delta = ""
        if baseline and name in baseline:
            d = s["acceptable"] - baseline[name]["acceptable"]
            delta = f"  ({d:+.1%} vs baseline)" if abs(d) >= 0.005 else ""
        cells = [
            f"{s['runs']:>4}",
            f"{s['acceptable']:>6.1%}",
            f"{s['wrong_per_hour']:>8.1f}",
            f"{s['detected']:>6.0%}",
            fmt(s["detect_s"], ">6.1f", "s"),
            fmt(s["lag_median"], ">4.1f", "s"),
            fmt(s["lag_p90"], ">5.1f", "s"),
            f"{s['never_shown']:>6}",
            f"{s['asr_load']:>5.2f}",
        ]
        print(f"  {name:<32} " + " ".join(cells) + delta)


def git_sha() -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True
        ).stdout.strip()
    except OSError:
        return "?"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quick", action="store_true", help="6 reciters, 2 passages, gated rooms only")
    ap.add_argument("--reciters", type=int, default=None, help="use the first N reciters")
    ap.add_argument("--passages", type=int, default=None)
    ap.add_argument("--rooms", default=None, help="comma-separated subset of: " + ", ".join(ROOMS))
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--save", type=Path, default=None, help="write all runs + summaries as JSON")
    ap.add_argument("--baseline", type=Path, default=None, help="a previous --save file to compare with")
    ap.add_argument("--check", action="store_true", help="exit 1 if below regression thresholds")
    args = ap.parse_args()

    reciters = RECITERS[: args.reciters or (6 if args.quick else len(RECITERS))]
    n_passages = args.passages or (2 if args.quick else 3)
    room_names = args.rooms.split(",") if args.rooms else (list(THRESHOLDS) if args.quick else list(ROOMS))
    rooms = {name: ROOMS[name] for name in room_names}

    index = get_index()
    q = index.quran
    transcriber = WhisperTranscriber()
    transcriber.load()
    plan = passages(q, index, n_passages, args.seed)
    print(f"device: {transcriber.active_device} | {len(reciters)} reciters x {len(plan)} passages x "
          f"{len(rooms)} rooms = {len(reciters) * len(plan) * len(rooms)} runs")  # fmt: skip
    for i, p in enumerate(plan):
        refs = [q.by_id(v).ref for v in p]
        print(f"  passage {i}: {refs[0]} .. {refs[-1]} ({len(p)} ayahs)")

    rng = random.Random(args.seed)
    runs: list[dict] = []
    started = time.perf_counter()
    for pi, verses in enumerate(plan):
        for reciter in reciters:
            clean, timeline = build_stream(q, reciter, verses)
            for room_name, room in rooms.items():
                join = round(rng.uniform(0.5, 3.0), 1)
                audio = degrade(clean, room, seed=args.seed + pi)
                r = run_one(transcriber, index, audio, timeline, join)
                runs.append(
                    {"reciter": reciter, "room": room_name, "passage": pi, "join": join, **r.to_dict()}
                )
                lag = f"{r.lag_median}s/{r.lag_p90}s"
                print(
                    f"  {reciter:<32} p{pi} {room_name:<6} right {r.acceptable:>5.0%}  "
                    f"wrong {r.wrong_jumps}  detect {r.detect_s}s  lag {lag}  missed {r.never_shown}"
                )

    by_room, by_reciter = summarize(runs, "room"), summarize(runs, "reciter")
    base = json.loads(args.baseline.read_text(encoding="utf-8")) if args.baseline else None
    print_table("By room", by_room, base and base["by_room"])
    print_table("By reciter (all rooms)", by_reciter, base and base["by_reciter"])
    print(f"\n{len(runs)} runs in {time.perf_counter() - started:.0f}s")

    if args.save:
        args.save.parent.mkdir(parents=True, exist_ok=True)
        meta = {
            "git": git_sha(),
            "date": time.strftime("%Y-%m-%d"),
            "device": transcriber.active_device,
            "seed": args.seed,
            "reciters": reciters,
            "rooms": {k: asdict(v) for k, v in rooms.items()},
        }
        payload = {"meta": meta, "by_room": by_room, "by_reciter": by_reciter, "runs": runs}
        args.save.write_text(json.dumps(payload, indent=1, ensure_ascii=False), encoding="utf-8")
        print(f"saved {args.save}")

    failed = []
    for room, (min_ok, max_wrong, min_found) in THRESHOLDS.items():
        s = by_room.get(room)
        if s and (s["acceptable"] < min_ok or s["wrong_per_hour"] > max_wrong or s["detected"] < min_found):
            failed.append(
                f"{room}: right {s['acceptable']:.1%} (min {min_ok:.0%}), "
                f"wrong/h {s['wrong_per_hour']} (max {max_wrong}), "
                f"found {s['detected']:.0%} (min {min_found:.0%})"
            )
    if args.check and failed:
        print("\nREGRESSION:\n  " + "\n  ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
