"""Voice activity detection: where in a buffer is someone reciting?

Two implementations behind one protocol:

* `EnergyVad` — loudness above an adaptive noise floor. The default: it keeps
  long tajweed elongations inside one chunk. Dependency-free and deterministic.
* `SileroVad` — the Silero model bundled with faster-whisper. Better at quiet
  speech in noise, but it splits sustained chanted vowels, so it is opt-in.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

import numpy as np

from rafiq.asr.audio import SAMPLE_RATE

Span = tuple[int, int]  # [start, end) in samples


class Vad(Protocol):
    def speech_spans(self, audio: np.ndarray) -> list[Span]:
        """Speech regions in `audio`, in order, as sample ranges."""
        ...


@dataclass(frozen=True, slots=True)
class SileroVad:
    threshold: float = 0.5
    min_silence_ms: int = 250  # gaps shorter than this stay inside one span
    speech_pad_ms: int = 60

    def speech_spans(self, audio: np.ndarray) -> list[Span]:
        from faster_whisper.vad import VadOptions, get_speech_timestamps

        opts = VadOptions(
            threshold=self.threshold,
            min_silence_duration_ms=self.min_silence_ms,
            speech_pad_ms=self.speech_pad_ms,
        )
        return [(s["start"], s["end"]) for s in get_speech_timestamps(audio, opts, sampling_rate=SAMPLE_RATE)]


class EnergyVad:
    """Loudness above an adaptive noise floor.

    The default for recitation. Tajweed stretches vowels for seconds (madd),
    and speech-trained models like Silero call those sustained melodic tones
    "not speech", cutting chunks mid-word. Loudness does not care whether
    the sound is spoken or chanted, only that the imam is louder than the room.

    The noise floor is learned from the quietest frames seen recently, so the
    same settings work for a silent studio file and a humming mosque. It is
    remembered across calls (a buffer that is all recitation has no silence
    to measure) and allowed to drift up slowly in case the room gets louder.

    The threshold is also capped at a fraction of the loudest recent level.
    Without that cap, listening that starts mid-recitation would learn the
    recitation itself as the "noise floor" and hear nothing until a pause.
    """

    def __init__(
        self,
        min_threshold: float = 0.005,  # RMS that always counts as silence (digital silence, hiss)
        floor_ratio: float = 2.5,  # speech must be this many times (~8 dB) louder than the noise floor
        frame_ms: int = 30,
        min_silence_ms: int = 250,
        floor_drift: float = 1.01,  # per call; lets the floor rise ~2x in 70 calls (~17 s)
        loud_fraction: float = 0.25,  # the threshold never exceeds this fraction of the loud level
    ) -> None:
        self.min_threshold = min_threshold
        self.floor_ratio = floor_ratio
        self.frame_ms = frame_ms
        self.min_silence_ms = min_silence_ms
        self.floor_drift = floor_drift
        self.loud_fraction = loud_fraction
        self.noise_floor: float | None = None
        self.loud_level: float | None = None

    def threshold(self) -> float:
        if self.noise_floor is None or self.loud_level is None:
            return self.min_threshold
        return max(
            self.min_threshold, min(self.noise_floor * self.floor_ratio, self.loud_level * self.loud_fraction)
        )

    def speech_spans(self, audio: np.ndarray) -> list[Span]:
        frame = SAMPLE_RATE * self.frame_ms // 1000
        n = len(audio) // frame
        if n == 0:
            return []
        rms = np.sqrt(np.mean(audio[: n * frame].reshape(n, frame) ** 2, axis=1))
        quiet, loud = float(np.percentile(rms, 10)), float(np.percentile(rms, 95))
        if self.noise_floor is None or self.loud_level is None:
            self.noise_floor, self.loud_level = quiet, loud
        else:
            self.noise_floor = min(self.noise_floor * self.floor_drift, quiet)
            self.loud_level = max(self.loud_level / self.floor_drift, loud)

        voiced = rms > self.threshold()
        spans: list[Span] = []
        start = None
        for i, v in enumerate(voiced):
            if v and start is None:
                start = i
            elif not v and start is not None:
                spans.append((start * frame, i * frame))
                start = None
        if start is not None:
            spans.append((start * frame, n * frame))
        # Merge spans separated by less than the minimum silence.
        gap = SAMPLE_RATE * self.min_silence_ms // 1000
        merged: list[Span] = []
        for sp in spans:
            if merged and sp[0] - merged[-1][1] < gap:
                merged[-1] = (merged[-1][0], sp[1])
            else:
                merged.append(sp)
        return merged
