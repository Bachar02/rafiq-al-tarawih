"""Re-score tracker changes on real ASR output, in seconds instead of an hour.

`audio_bench.py --record DIR` saves what Whisper produced for every run (texts
and timing). Segmentation and transcription never depend on the tracker, so
replaying those events through a modified tracker gives exactly the metrics
the full benchmark would, minus the ASR time.

    py eval/tracker_replay.py eval/results/transcripts
    py eval/tracker_replay.py eval/results/transcripts --set cold_start_confidence=0.2
    py eval/tracker_replay.py eval/results/transcripts --set decay=0.5 --set miss_cost=0.4
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import fields, replace
from pathlib import Path

from audio_bench import print_table, summarize
from audiolib import replay_tracker, score_run
from rafiq.matching import MatchConfig, Matcher, get_index
from rafiq.tracking import Tracker, TrackerConfig


def parse_overrides(pairs: list[str], cls=TrackerConfig) -> dict:
    types = {f.name: f.type for f in fields(cls)}
    out = {}
    for pair in pairs:
        key, _, value = pair.partition("=")
        if key not in types:
            raise SystemExit(f"unknown {cls.__name__} field {key!r}; known: {', '.join(types)}")
        if value.lower() == "none":
            out[key] = None
        else:
            out[key] = int(value) if types[key] in ("int", int) else float(value)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("recordings", type=Path)
    ap.add_argument(
        "--set", action="append", default=[], metavar="FIELD=VALUE", help="override a TrackerConfig field"
    )
    ap.add_argument(
        "--match", action="append", default=[], metavar="FIELD=VALUE", help="override MatchConfig"
    )
    ap.add_argument("--by-reciter", action="store_true")
    args = ap.parse_args()

    config = replace(TrackerConfig(), **parse_overrides(args.set))
    matcher = Matcher(get_index(), replace(MatchConfig(), **parse_overrides(args.match, MatchConfig)))
    runs = []
    for path in sorted(args.recordings.glob("*.json")):
        rec = json.loads(path.read_text(encoding="utf-8"))
        heard, ready = replay_tracker(rec, Tracker(matcher, config))
        timeline = [tuple(t) for t in rec["timeline"]]
        r = score_run(heard, ready, timeline, rec["join"], rec["seconds"])
        runs.append({"reciter": rec["reciter"], "room": rec["room"], **r.to_dict()})
    if not runs:
        raise SystemExit(f"no recordings in {args.recordings}; make some with audio_bench.py --record")

    print(
        f"{len(runs)} recorded runs | tracker: {args.set or 'default'} | matcher: {args.match or 'default'}"
    )
    print_table("By room", summarize(runs, "room"))
    if args.by_reciter:
        print_table("By reciter", summarize(runs, "reciter"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
