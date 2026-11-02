"""Shared tools for real-audio evaluation (audio_check.py, audio_bench.py).

Builds continuous recitations from EveryAyah's per-ayah recordings, where the
ground-truth timing of every ayah is known exactly, degrades them like a
mosque would, and replays them through a `Listener` on a simulated real-time
clock that behaves exactly like the live server.

Audio is cached in eval/audio/ (gitignored). EveryAyah recordings are for
personal/research use; never commit them.
"""

from __future__ import annotations

import json
import math
import statistics
import sys
import time
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
from rafiq import evaluation
from rafiq.asr import SAMPLE_RATE, Heard, Listener, load_audio
from rafiq.quran import Quran
from rafiq.simulate import Step
from rafiq.tracking import Tracker

AUDIO_DIR = Path(__file__).resolve().parent / "audio"
EVERYAYAH = "https://everyayah.com/data/{reciter}/{surah:03d}{ayah:03d}.mp3"
GAP_S = 0.5  # silence inserted between ayahs, like an imam's pause

Timeline = list[tuple[float, float, int]]  # (start_s, end_s, verse_id) per ayah


def fetch(reciter: str, surah: int, ayah: int) -> Path:
    path = AUDIO_DIR / reciter / f"{surah:03d}{ayah:03d}.mp3"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        url = EVERYAYAH.format(reciter=reciter, surah=surah, ayah=ayah)
        print(f"  downloading {url}", file=sys.stderr)
        tmp = path.with_suffix(".part")
        urllib.request.urlretrieve(url, tmp)
        tmp.replace(path)  # never leave a truncated file in the cache
    return path


def build_stream(q: Quran, reciter: str, verse_ids: list[int]) -> tuple[np.ndarray, Timeline]:
    """Concatenate ayahs (may cross surahs) into one recitation, with exact timing."""
    gap = np.zeros(int(GAP_S * SAMPLE_RATE), dtype=np.float32)
    parts, timeline, t = [gap], [], GAP_S
    for vid in verse_ids:
        v = q.by_id(vid)
        audio = load_audio(fetch(reciter, v.surah, v.ayah))
        timeline.append((t, t + len(audio) / SAMPLE_RATE, vid))
        parts += [audio, gap]
        t += len(audio) / SAMPLE_RATE + GAP_S
    return np.concatenate(parts), timeline


@dataclass(frozen=True)
class Room:
    """Acoustics of where the listener sits."""

    rt60: float = 0.0  # reverb time in seconds (mosque halls: ~1-2.5)
    drr_db: float = 0.0  # direct-to-reverberant ratio: ~+5 near a loudspeaker, ~-5 at the back
    snr_db: float | None = None  # background noise; None = silent room


def degrade(audio: np.ndarray, room: Room, seed: int) -> np.ndarray:
    """A crude mosque: an exponentially decaying reverb tail plus white noise."""
    rng = np.random.default_rng(seed)
    out = audio
    if room.rt60 > 0:
        n = int(room.rt60 * SAMPLE_RATE)
        tail = rng.standard_normal(n).astype(np.float32) * np.exp(-6.9 * np.arange(n) / n).astype(np.float32)
        tail[0] = 0.0
        tail *= np.sqrt(10 ** (-room.drr_db / 10) / np.sum(tail**2))  # tail energy vs the direct path
        tail[0] = 1.0
        wet = np.convolve(out, tail)[: len(out)]
        out = wet / max(1e-6, np.abs(wet).max()) * np.abs(audio).max()
    if room.snr_db is not None:
        power = np.mean(out**2)
        out = out + rng.standard_normal(len(out)).astype(np.float32) * np.sqrt(
            power / 10 ** (room.snr_db / 10)
        )
    return out.astype(np.float32)


def replay_realtime(listener: Listener, audio: np.ndarray, block_s: float = 0.25):
    """Run the listener exactly as the live server does, on a simulated clock.

    Audio "arrives" in real time in 250 ms blocks. Whenever the worker is free
    it takes ALL audio that has arrived since its last feed (the server's
    catch-up behaviour), and the clock advances by the real processing time.
    Returns the events and, for each, the moment it would reach the screen,
    so lag and backlog are what a user would see on this machine.
    """
    block = int(block_s * SAMPLE_RATE)
    heard: list[Heard] = []
    ready: list[float] = []
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


def percentile(sorted_values: list[float], pct: float) -> float:
    """Nearest-rank percentile: always one of the values, and never below the median."""
    rank = math.ceil(pct / 100 * len(sorted_values))
    return sorted_values[max(rank, 1) - 1]


# -- recordings: replay the tracker over real ASR output in milliseconds ----


def save_recording(path: Path, heard: list[Heard], ready: list[float], timeline: Timeline, **meta) -> None:
    """Keep what ASR produced for one run, so tracker changes can be re-scored offline.

    Segmentation and transcription never depend on the tracker, so replaying
    these events through a different tracker is exact: same texts, same
    timing, only the tracker's decisions change.
    """
    events = [
        {"text": h.text, "start": h.start, "end": h.end, "asr_ms": h.asr_ms, "final": h.final, "ready": t}
        for h, t in zip(heard, ready, strict=True)
    ]
    payload = {**meta, "timeline": timeline, "events": events}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def replay_tracker(recording: dict, tracker: Tracker) -> tuple[list[Heard], list[float]]:
    """Re-run only the tracker over a recording: finals commit, partials preview."""
    heard, ready = [], []
    for e in recording["events"]:
        state = tracker.update(e["text"]) if e["final"] else tracker.preview(e["text"])
        heard.append(Heard(e["text"], e["start"], e["end"], e["asr_ms"], state, e["final"]))
        ready.append(e["ready"])
    return heard, ready


def heard_verses(timeline: Timeline, t0: float, t1: float) -> tuple[int, ...]:
    """Verses whose audio overlaps [t0, t1] by more than a sliver."""
    return tuple(v for s, e, v in timeline if s < t1 - 0.15 and e > t0 + 0.15)


@dataclass
class RunResult:
    seconds: float
    ayahs: int
    finals: int
    acceptable: float  # finals showing an ayah within ±1 of one heard in the chunk
    exact: float
    wrong_jumps: int
    detect_s: float | None  # seconds of listening until a correct ayah is first on screen
    lag_median: float | None  # ayah starts -> on screen, seconds
    lag_p90: float | None
    never_shown: int  # ayahs (after detection) the screen never showed
    asr_load: float  # transcription time / audio time (1.0 = saturated, catching up)

    def to_dict(self) -> dict:
        return asdict(self)


def score_run(
    heard: list[Heard], ready: list[float], timeline: Timeline, join: float, seconds: float
) -> RunResult:
    """All product metrics for one replayed stream. `join` = seconds missed at the start."""
    # Accuracy on finals: they are what the tracker commits.
    steps, predicted = [], []
    for h in heard:
        if h.final:
            spoken = heard_verses(timeline, h.start + join, h.end + join)
            steps.append(Step(h.text, spoken[-1] if spoken else None, None, spoken))
            predicted.append(h.state.verse_id)
    r = evaluation.score(predicted, steps)

    # Detection: first moment a correct ayah (±1 of what is being heard) is on screen.
    detect = None
    for h, t in zip(heard, ready, strict=True):
        shown = h.state.verse_id
        spoken = heard_verses(timeline, h.start + join, h.end + join)
        if shown and spoken and min(abs(shown - v) for v in spoken) <= 1:
            detect = t
            break

    # Lag: for each ayah that starts after detection, until the screen shows it.
    lags: list[float | None] = []
    if detect is not None:
        for start, _, verse in timeline:
            s = start - join
            if s < detect:
                continue
            t = next(
                (ready[i] for i, h in enumerate(heard) if h.state.showing == verse and ready[i] >= s), None
            )
            lags.append(None if t is None else t - s)
    shown_lags = sorted(x for x in lags if x is not None)

    return RunResult(
        seconds=round(seconds, 1),
        ayahs=len(timeline),
        finals=len(steps),
        acceptable=round(r.acceptable, 3),
        exact=round(r.accuracy, 3),
        wrong_jumps=r.wrong_jumps,
        detect_s=None if detect is None else round(detect, 2),
        lag_median=round(statistics.median(shown_lags), 2) if shown_lags else None,
        lag_p90=round(percentile(shown_lags, 90), 2) if shown_lags else None,
        never_shown=lags.count(None),
        asr_load=round(sum(h.asr_ms for h in heard) / 1000 / max(seconds, 1e-6), 2),
    )
