"""End-to-end check of one passage on real audio: audio -> ASR -> tracker -> metrics.

Streams an EveryAyah recitation through the same `Listener` the live server
uses, on a simulated real-time clock, and prints every chunk with its truth.
For the multi-reciter regression suite, see audio_bench.py.

    py eval/audio_check.py --surah 78 --from 1 --to 20
    py eval/audio_check.py --surah 55 --from 10 --to 30 --reverb 1.5 --drr 0 --snr 15 --join 4
    py eval/audio_check.py --surah 93 --hint surah --reciter Husary_128kbps
"""

from __future__ import annotations

import argparse
import sys

from audiolib import Room, build_stream, degrade, heard_verses, replay_realtime, score_run
from rafiq.asr import (
    SAMPLE_RATE,
    EnergyVad,
    Listener,
    ListenerConfig,
    Segmenter,
    SileroVad,
    WhisperTranscriber,
)
from rafiq.matching import Matcher, get_index
from rafiq.tracking import Tracker


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--surah", type=int, default=78)
    ap.add_argument("--from", dest="first", type=int, default=1)
    ap.add_argument("--to", dest="last", type=int, default=15)
    ap.add_argument("--reciter", default="Alafasy_128kbps", help="an everyayah.com/data folder name")
    ap.add_argument("--reverb", type=float, default=0.0, help="reverb time RT60 in seconds (mosque: 1-2.5)")
    ap.add_argument("--drr", type=float, default=0.0, help="direct-to-reverberant dB (near +5, far -5)")
    ap.add_argument("--snr", type=float, default=None, help="add noise at this SNR in dB (lower = noisier)")
    ap.add_argument("--join", type=float, default=0.0, help="start listening this many seconds late")
    ap.add_argument("--hint", choices=["none", "surah", "juz"], default="none")
    ap.add_argument("--vad", choices=["energy", "silero"], default="energy")
    ap.add_argument("--partial", type=float, default=0.5, help="live preview every N s of speech (0: off)")
    ap.add_argument("--verbose", action="store_true", help="also print partial (preview) events")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    index = get_index()
    q = index.quran
    surah = q.surah(args.surah)
    verses = [q.verse(args.surah, a).id for a in range(args.first, min(args.last, surah.ayah_count) + 1)]
    audio, timeline = build_stream(q, args.reciter, verses)
    audio = degrade(audio, Room(args.reverb, args.drr, args.snr), args.seed)[int(args.join * SAMPLE_RATE) :]

    tracker = Tracker(Matcher(index))
    if args.hint == "surah":
        tracker.hint(surah.first_verse_id, surah.last_verse_id)
    elif args.hint == "juz":
        tracker.hint(*q.juz_span(q.juz_of(verses[0])))
    transcriber = WhisperTranscriber()
    transcriber.load()  # load + warm up outside the timed run, as the server does at connect
    vad = SileroVad() if args.vad == "silero" else EnergyVad()
    listener = Listener(Segmenter(vad), transcriber, tracker, ListenerConfig(partial_every_s=args.partial))

    heard, ready = replay_realtime(listener, audio)
    ref = lambda v: q.by_id(v).ref if v else "-"  # noqa: E731
    print(f"{'time':>11}  {'asr':>5}  {'truth':<14} {'shown':<8} heard")
    for h in heard:
        if not h.final and not args.verbose:
            continue
        t0, t1 = h.start + args.join, h.end + args.join
        truth = ",".join(ref(v) for v in heard_verses(timeline, t0, t1)) or "-"
        label = truth if h.final else "(preview)"
        print(f"{t0:5.1f}-{t1:5.1f}  {h.asr_ms:>4}ms {label:<14} {ref(h.state.verse_id):<8} {h.text}")

    r = score_run(heard, ready, timeline, args.join, len(audio) / SAMPLE_RATE)
    print(
        f"\n{r.finals} chunks over {r.seconds:.0f}s on {transcriber.active_device} | "
        f"right ayah (±1) {r.acceptable:.0%} | exact {r.exact:.0%} | wrong jumps {r.wrong_jumps} | "
        f"detected at {r.detect_s}s | ASR load {r.asr_load:.2f}"
    )
    print(f"display lag (ayah starts -> on screen): median {r.lag_median}s, p90 {r.lag_p90}s, "
          f"never shown {r.never_shown}")  # fmt: skip
    return 0


if __name__ == "__main__":
    sys.exit(main())
