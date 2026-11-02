"""The live pipeline: audio in, "where is the imam?" out.

    samples -> Segmenter -> Transcriber -> Tracker -> Heard events

Two kinds of event keep the display real-time:

* **partial** — about once a second while the imam is still reciting, the
  words so far in the current breath are transcribed and *previewed* by the
  tracker. The screen follows him mid-ayah instead of waiting for a pause.
* **final** — when he pauses, the whole chunk is transcribed once more and
  *committed* to the tracker. Only finals count as evidence, so the same
  words are never counted twice.

One `Listener` per audio stream (a mic session, a file). It is synchronous
and holds no threads: callers decide how to schedule it (the server runs it
off the event loop; scripts call it directly, faster than real time). Partial
cadence is measured in audio time, so results do not depend on machine speed.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

import numpy as np

from rafiq.asr.audio import SAMPLE_RATE
from rafiq.asr.segmenter import Segment, Segmenter
from rafiq.asr.transcriber import Transcriber
from rafiq.tracking import Tracker, TrackState


@dataclass(frozen=True, slots=True)
class ListenerConfig:
    # Each Whisper call costs ~0.4 s on a laptop CPU, so 0.5 s is about the
    # fastest sustainable cadence; the server coalesces audio if it falls behind.
    partial_every_s: float = 0.5  # 0 disables partials (finals only)
    min_partial_s: float = 0.6  # less speech than this is too little to transcribe


@dataclass(frozen=True, slots=True)
class Heard:
    """One recognised stretch of audio and what the app should now show."""

    text: str  # transcription, as Whisper wrote it (with diacritics)
    start: float  # seconds since the stream started
    end: float
    asr_ms: int  # time spent transcribing
    state: TrackState
    final: bool  # False: a live preview of an unfinished chunk


class Listener:
    def __init__(
        self,
        segmenter: Segmenter,
        transcriber: Transcriber,
        tracker: Tracker,
        config: ListenerConfig = ListenerConfig(),
    ) -> None:
        self.segmenter = segmenter
        self.transcriber = transcriber
        self.tracker = tracker
        self.config = config
        self._since_partial = 0  # samples since the last partial or final

    def feed(self, samples: np.ndarray) -> list[Heard]:
        """Push audio (16 kHz mono float32, any length); returns events it produced.

        Feeding a large block at once yields at most one partial, for the
        latest audio: a caller that fell behind catches up instead of
        transcribing stale previews.
        """
        out = [self._recognise(seg, final=True) for seg in self.segmenter.push(samples)]
        self._since_partial += len(samples)
        if out:
            self._since_partial = 0
        elif self.config.partial_every_s and self._since_partial >= self.config.partial_every_s * SAMPLE_RATE:
            seg = self.segmenter.in_progress(self.config.min_partial_s)
            if seg is not None:
                self._since_partial = 0
                out.append(self._recognise(seg, final=False))
        return out

    def flush(self) -> list[Heard]:
        """End of stream."""
        return [self._recognise(seg, final=True) for seg in self.segmenter.flush()]

    def _recognise(self, seg: Segment, final: bool) -> Heard:
        t = time.perf_counter()
        text = self.transcriber.transcribe(seg.audio)
        asr_ms = int((time.perf_counter() - t) * 1000)
        state = self.tracker.update(text) if final else self.tracker.preview(text)
        return Heard(text=text, start=seg.start, end=seg.end, asr_ms=asr_ms, state=state, final=final)
