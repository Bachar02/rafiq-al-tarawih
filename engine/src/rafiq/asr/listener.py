"""The live pipeline: audio in, "where is the imam?" out.

    samples -> Segmenter -> Transcriber -> Tracker -> Heard events

One `Listener` per audio stream (a mic session, a file). It is synchronous
and holds no threads: callers decide how to schedule it (the server runs it
off the event loop; scripts call it directly, faster than real time).
"""

from __future__ import annotations

import time
from dataclasses import dataclass

import numpy as np

from rafiq.asr.segmenter import Segment, Segmenter
from rafiq.asr.transcriber import Transcriber
from rafiq.tracking import Tracker, TrackState


@dataclass(frozen=True, slots=True)
class Heard:
    """One recognised chunk and what the app should now show."""

    text: str  # transcription, as Whisper wrote it (with diacritics)
    start: float  # seconds since the stream started
    end: float
    asr_ms: int  # time spent transcribing this chunk
    state: TrackState


class Listener:
    def __init__(self, segmenter: Segmenter, transcriber: Transcriber, tracker: Tracker) -> None:
        self.segmenter = segmenter
        self.transcriber = transcriber
        self.tracker = tracker

    def feed(self, samples: np.ndarray) -> list[Heard]:
        """Push audio (16 kHz mono float32, any length); returns chunks completed by it."""
        return [self._recognise(seg) for seg in self.segmenter.push(samples)]

    def flush(self) -> list[Heard]:
        """End of stream."""
        return [self._recognise(seg) for seg in self.segmenter.flush()]

    def _recognise(self, seg: Segment) -> Heard:
        t = time.perf_counter()
        text = self.transcriber.transcribe(seg.audio)
        asr_ms = int((time.perf_counter() - t) * 1000)
        state = self.tracker.update(text)
        return Heard(text=text, start=seg.start, end=seg.end, asr_ms=asr_ms, state=state)
