"""Cut a live audio stream into recitation chunks at natural pauses.

Imams breathe and pause between ayahs. Cutting at those pauses (rather than
every N seconds) keeps words whole, which is what both Whisper and the matcher
want. When a reciter runs on without pausing, the chunk is cut at the latest
short pause inside it, or hard-cut at `max_chunk_s` as a last resort, so
latency stays bounded.

Feed it any block size; it re-runs VAD on the pending buffer at most every
`analyze_every_s`, which keeps the cost tiny (the buffer is a few seconds).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from rafiq.asr.audio import SAMPLE_RATE
from rafiq.asr.vad import Vad


@dataclass(frozen=True, slots=True)
class SegmenterConfig:
    pause_s: float = 0.35  # silence that ends a chunk
    min_chunk_s: float = 1.0  # shorter speech waits to be merged with what follows...
    lone_pause_s: float = 1.0  # ...unless followed by this much silence (a short ayah)
    min_speech_s: float = 0.3  # blips shorter than this are dropped (clicks, coughs)
    max_chunk_s: float = 7.0  # never hold more speech than this
    pad_s: float = 0.1  # audio kept around each chunk so word edges are not clipped
    analyze_every_s: float = 0.25


@dataclass(frozen=True, slots=True)
class Segment:
    audio: np.ndarray
    start: float  # seconds since the stream started
    end: float


class Segmenter:
    def __init__(self, vad: Vad, config: SegmenterConfig = SegmenterConfig()) -> None:
        self.vad = vad
        self.config = config
        self.reset()

    def reset(self) -> None:
        self._buf = np.zeros(0, dtype=np.float32)
        self._offset = 0  # absolute sample index of _buf[0]
        self._unanalyzed = 0

    def push(self, samples: np.ndarray) -> list[Segment]:
        """Add audio; returns any chunks that are now complete."""
        self._buf = np.concatenate([self._buf, samples.astype(np.float32, copy=False)])
        self._unanalyzed += len(samples)
        out: list[Segment] = []
        while self._unanalyzed >= self._s(self.config.analyze_every_s):
            self._unanalyzed = 0
            seg = self._try_cut()
            if seg is None:
                break
            out.append(seg)
            self._unanalyzed = len(self._buf)  # re-check the remainder straight away
        return out

    def flush(self) -> list[Segment]:
        """End of stream: return whatever speech is left."""
        spans = self.vad.speech_spans(self._buf)
        out = []
        if spans and spans[-1][1] - spans[0][0] >= self._s(self.config.min_speech_s):
            out.append(self._emit(spans[0][0], spans[-1][1], cut=len(self._buf)))
        self.reset()
        return out

    # -- internals -------------------------------------------------------

    @staticmethod
    def _s(seconds: float) -> int:
        return int(seconds * SAMPLE_RATE)

    def _try_cut(self) -> Segment | None:
        cfg, buf = self.config, self._buf
        spans = self.vad.speech_spans(buf)
        if not spans:
            self._drop(max(0, len(buf) - self._s(cfg.pad_s)))  # silence: keep only a short tail
            return None

        first, last_end = spans[0][0], spans[-1][1]
        speech = last_end - first
        silence_after = len(buf) - last_end

        if silence_after >= self._s(cfg.pause_s):
            if speech >= self._s(cfg.min_chunk_s):
                return self._emit(first, last_end, cut=last_end)
            if silence_after >= self._s(cfg.lone_pause_s):
                if speech >= self._s(cfg.min_speech_s):
                    return self._emit(first, last_end, cut=last_end)
                self._drop(last_end)  # a blip
            return None

        if len(buf) - first >= self._s(cfg.max_chunk_s):
            # Running on without a full pause: cut at the latest short gap that
            # leaves a usable chunk, else hard-cut at the limit.
            inner = [e for _, e in spans[:-1] if e - first >= self._s(cfg.min_chunk_s)]
            cut = inner[-1] if inner else first + self._s(cfg.max_chunk_s)
            return self._emit(first, cut, cut=cut)
        return None

    def _emit(self, start: int, end: int, cut: int) -> Segment:
        pad = self._s(self.config.pad_s)
        lo, hi = max(0, start - pad), min(len(self._buf), end + pad)
        seg = Segment(
            audio=self._buf[lo:hi].copy(),
            start=(self._offset + lo) / SAMPLE_RATE,
            end=(self._offset + hi) / SAMPLE_RATE,
        )
        self._drop(cut)
        return seg

    def _drop(self, n: int) -> None:
        self._buf = self._buf[n:]
        self._offset += n
