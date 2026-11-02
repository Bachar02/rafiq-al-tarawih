"""End-to-end check on real recitation audio: audio -> ASR -> tracker -> metrics.

Builds one continuous recitation from EveryAyah's per-ayah recordings (so the
ground-truth timing of every ayah is known exactly), optionally degrades it
like a mosque would (reverb, noise), joins late, and streams it through the
same `Listener` the live server uses — in blocks, as a microphone would, but
faster than real time.

    py eval/audio_check.py --surah 78 --from 1 --to 20
    py eval/audio_check.py --surah 55 --from 10 --to 30 --reverb 1.5 --drr 0 --snr 15 --join 4
    py eval/audio_check.py --surah 93 --hint surah

Audio is downloaded on first use into eval/audio/ (gitignored). EveryAyah
recordings are for personal/research use; never commit them.
"""

from __future__ import annotations

import argparse
import sys
import time
import urllib.request
from pathlib import Path

import numpy as np
from rafiq import evaluation
from rafiq.asr import (
    SAMPLE_RATE,
    EnergyVad,
    Listener,
    ListenerConfig,
    Segmenter,
    SileroVad,
    WhisperTranscriber,
    load_audio,
)
from rafiq.matching import Matcher, get_index
from rafiq.simulate import Step
from rafiq.tracking import Tracker

AUDIO_DIR = Path(__file__).resolve().parent / "audio"
EVERYAYAH = "https://everyayah.com/data/{reciter}/{surah:03d}{ayah:03d}.mp3"
GAP_S = 0.5  # silence inserted between ayahs, like an imam's pause


def fetch(reciter: str, surah: int, ayah: int) -> Path:
    path = AUDIO_DIR / reciter / f"{surah:03d}{ayah:03d}.mp3"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        url = EVERYAYAH.format(reciter=reciter, surah=surah, ayah=ayah)
        print(f"  downloading {url}", file=sys.stderr)
        urllib.request.urlretrieve(url, path)
    return path


def build_stream(
    q, reciter: str, surah: int, first: int, last: int
) -> tuple[np.ndarray, list[tuple[float, float, int]]]:
    """Concatenated audio and [(start_s, end_s, verse_id)] for each ayah."""
    gap = np.zeros(int(GAP_S * SAMPLE_RATE), dtype=np.float32)
    parts, timeline, t = [gap], [], GAP_S
    for ayah in range(first, last + 1):
        audio = load_audio(fetch(reciter, surah, ayah))
        timeline.append((t, t + len(audio) / SAMPLE_RATE, q.verse(surah, ayah).id))
        parts += [audio, gap]
        t += len(audio) / SAMPLE_RATE + GAP_S
    return np.concatenate(parts), timeline


def degrade(audio: np.ndarray, reverb_s: float, drr_db: float, snr_db: float | None, seed: int) -> np.ndarray:
    """A crude mosque: a decaying reverb tail plus white noise.

    The tail's energy is set by the direct-to-reverberant ratio (DRR): ~+5 dB
    sitting near a loudspeaker, ~0 dB mid-hall, ~-5 dB at the back of a big
    echoing room. `reverb_s` is the RT60 (time for the tail to fade 60 dB).
    """
    rng = np.random.default_rng(seed)
    out = audio
    if reverb_s > 0:
        n = int(reverb_s * SAMPLE_RATE)
        tail = rng.standard_normal(n).astype(np.float32) * np.exp(-6.9 * np.arange(n) / n).astype(np.float32)
        tail[0] = 0.0
        tail *= np.sqrt(10 ** (-drr_db / 10) / np.sum(tail**2))  # tail energy relative to the direct path
        ir = tail
        ir[0] = 1.0
        wet = np.convolve(out, ir)[: len(out)]
        out = wet / max(1e-6, np.abs(wet).max()) * np.abs(audio).max()
    if snr_db is not None:
        power = np.mean(out**2)
        out = out + rng.standard_normal(len(out)).astype(np.float32) * np.sqrt(power / 10 ** (snr_db / 10))
    return out.astype(np.float32)


def replay_realtime(listener: Listener, audio: np.ndarray, block_s: float = 0.25):
    """Run the listener exactly as the live server does, on a simulated clock.

    Audio "arrives" in real time in 250 ms blocks. Whenever the worker is free
    it takes ALL audio that has arrived since its last feed (the server's
    catch-up behaviour), and the clock advances by the real processing time.
    Returns the events and, for each, the moment it would reach the screen.
    So lag and backlog here are what a user would see on this machine.
    """
    block = int(block_s * SAMPLE_RATE)
    heard, ready = [], []
    clock, pos = 0.0, 0
    while pos < len(audio):
        clock = max(clock, (pos + block) / SAMPLE_RATE)  # wait for at least one new block
        avail = min(len(audio), max(pos + block, int(clock * SAMPLE_RATE) // block * block))
        t = time.perf_counter()
        events = listener.feed(audio[pos:avail])
        clock += time.perf_counter() - t
        pos = avail
        heard += events
        ready += [clock] * len(events)
    t = time.perf_counter()
    events = listener.flush()
    clock += time.perf_counter() - t
    return heard + events, ready + [clock] * len(events)


def display_lags(heard, ready, timeline, join: float) -> list[float | None]:
    """Seconds from each ayah's start until the screen first shows it (None: never).

    Ayahs that began before listening started, and the first ayah heard
    (detection needs a few words), are skipped: this measures keeping up.
    """
    lags: list[float | None] = []
    detected = next((ready[i] for i, h in enumerate(heard) if h.state.verse_id), None)
    if detected is None:
        return [None for s, _, _ in timeline if s >= join]
    for start, _, verse in timeline:
        if start - join < 0 or start - join < detected:
            continue
        t = next(
            (ready[i] for i, h in enumerate(heard) if h.state.showing == verse and ready[i] >= start - join),
            None,
        )
        lags.append(None if t is None else t - (start - join))
    return lags


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--surah", type=int, default=78)
    ap.add_argument("--from", dest="first", type=int, default=1)
    ap.add_argument("--to", dest="last", type=int, default=15)
    ap.add_argument("--reciter", default="Alafasy_128kbps", help="an everyayah.com/data folder name")
    ap.add_argument("--reverb", type=float, default=0.0, help="reverb time RT60 in seconds (mosque: 1-2.5)")
    ap.add_argument(
        "--drr", type=float, default=0.0, help="direct-to-reverberant ratio in dB (near +5, far -5)"
    )
    ap.add_argument("--snr", type=float, default=None, help="add noise at this SNR in dB (lower = noisier)")
    ap.add_argument("--join", type=float, default=0.0, help="start listening this many seconds late")
    ap.add_argument("--hint", choices=["none", "surah", "juz"], default="none")
    ap.add_argument("--vad", choices=["energy", "silero"], default="energy")
    ap.add_argument("--vad-ratio", type=float, default=None, help="EnergyVad floor_ratio override")
    ap.add_argument("--beam", type=int, default=None, help="Whisper beam size override")
    ap.add_argument("--partial", type=float, default=0.5, help="live preview every N s of speech (0: off)")
    ap.add_argument("--verbose", action="store_true", help="also print partial (preview) events")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    index = get_index()
    q = index.quran
    audio, timeline = build_stream(q, args.reciter, args.surah, args.first, args.last)
    audio = degrade(audio, args.reverb, args.drr, args.snr, args.seed)
    skip = int(args.join * SAMPLE_RATE)
    audio = audio[skip:]

    tracker = Tracker(Matcher(index))
    if args.hint == "surah":
        s = q.surah(args.surah)
        tracker.hint(s.first_verse_id, s.last_verse_id)
    elif args.hint == "juz":
        tracker.hint(*q.juz_span(q.juz_of(q.verse(args.surah, args.first).id)))
    if args.vad == "silero":
        vad = SileroVad()
    else:
        vad = EnergyVad(floor_ratio=args.vad_ratio) if args.vad_ratio else EnergyVad()
    transcriber = WhisperTranscriber(beam_size=args.beam) if args.beam else WhisperTranscriber()
    listener = Listener(Segmenter(vad), transcriber, tracker, ListenerConfig(partial_every_s=args.partial))
    transcriber.load()  # load + warm up outside the timed run, as the server does at connect

    heard, ready = replay_realtime(listener, audio)
    lags = display_lags(heard, ready, timeline, args.join)

    # Accuracy is scored on finals only: they are what the tracker commits.
    steps, predicted = [], []
    print(f"{'time':>11}  {'asr':>5}  {'truth':<14} {'shown':<8} heard")
    for h in heard:
        if not h.final:
            if args.verbose:
                shown = q.by_id(h.state.verse_id).ref if h.state.verse_id else "-"
                span = f"{h.start + args.join:5.1f}-{h.end + args.join:5.1f}"
                print(f"{span}  {h.asr_ms:>4}ms {'(preview)':<14} {shown:<8} {h.text}")
            continue
        t0, t1 = h.start + args.join, h.end + args.join
        spoken = tuple(v for s, e, v in timeline if s < t1 - 0.15 and e > t0 + 0.15)
        steps.append(Step(h.text, spoken[-1] if spoken else None, None, spoken))
        predicted.append(h.state.verse_id)
        truth = ",".join(q.by_id(v).ref for v in spoken) or "-"
        shown = q.by_id(h.state.verse_id).ref if h.state.verse_id else "-"
        print(f"{t0:5.1f}-{t1:5.1f}  {h.asr_ms:>4}ms {truth:<14} {shown:<8} {h.text}")

    r = evaluation.score(predicted, steps)
    duration = len(audio) / SAMPLE_RATE
    asr_total = sum(h.asr_ms for h in heard) / 1000
    print(
        f"\n{len(heard)} chunks over {duration:.0f}s | "
        f"right ayah (±1) {r.acceptable:.0%} | exact {r.accuracy:.0%} | "
        f"wrong jumps {r.wrong_jumps} | detected after {r.time_to_lock} chunk(s) | "
        f"ASR {asr_total / duration:.2f}x real time"
    )
    if lags:
        shown = [x for x in lags if x is not None]
        print(
            f"display lag (ayah starts -> on screen): median {np.median(shown):.1f}s, "
            f"worst {max(shown):.1f}s, "
            f"ayahs never shown {lags.count(None)}/{len(lags)}"
            if shown
            else f"display lag: no ayah was ever shown ({len(lags)} ayahs)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
