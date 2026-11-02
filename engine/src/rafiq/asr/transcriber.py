"""Speech -> text, behind a one-method protocol.

`WhisperTranscriber` wraps a Whisper model fine-tuned on Quran recitation
(Tarteel's whisper-base-ar-quran, converted for faster-whisper). It is the
laptop baseline; the phone will use the same model exported to ONNX behind the
same protocol (Phase 6).
"""

from __future__ import annotations

import os
import threading
from dataclasses import dataclass, field
from typing import Protocol

import numpy as np

from rafiq.asr.audio import SAMPLE_RATE

DEFAULT_MODEL = "OdyAsh/faster-whisper-base-ar-quran"  # Apache-2.0, CTranslate2 build of Tarteel's model
DEFAULT_REVISION = "8578bafd427d122f671b187706650e76edf6f86f"  # pinned: results must be reproducible


class Transcriber(Protocol):
    def transcribe(self, audio: np.ndarray) -> str:
        """Text recited in `audio` (16 kHz mono float32); empty if nothing."""
        ...


@dataclass
class WhisperTranscriber:
    model: str = field(default_factory=lambda: os.environ.get("RAFIQ_ASR_MODEL", DEFAULT_MODEL))
    revision: str | None = field(
        default_factory=lambda: os.environ.get("RAFIQ_ASR_REVISION", DEFAULT_REVISION)
    )
    compute_type: str = "int8"  # fast on CPU, accuracy indistinguishable for this task
    device: str = "cpu"
    beam_size: int = 1  # greedy: ~2x faster, and the matcher absorbs the odd error
    no_speech_threshold: float = 0.6  # drop segments Whisper itself thinks are not speech

    def __post_init__(self) -> None:
        self._model = None
        self._lock = threading.Lock()  # one decode at a time; the server shares one model

    def load(self) -> None:
        """Load and warm up (downloads ~150 MB on first use). Called lazily by `transcribe`.

        Each call costs ~0.4 s on a laptop CPU *whatever the audio length*:
        Whisper always encodes a 30 s window. Latency therefore comes from how
        often we call it, which is the listener's job to manage.
        """
        with self._lock:
            if self._model is None:
                from faster_whisper import WhisperModel

                model = WhisperModel(
                    self.model, device=self.device, compute_type=self.compute_type, revision=self.revision
                )
                # Warm-up: the first decode allocates buffers and takes ~5x longer.
                # Pay it here, at load time, not on the listener's first chunk.
                warm, _ = model.transcribe(np.zeros(SAMPLE_RATE, dtype=np.float32), language="ar")
                list(warm)  # transcribe() is lazy: decoding happens when the segments are consumed
                self._model = model

    def transcribe(self, audio: np.ndarray) -> str:
        if self._model is None:
            self.load()
        with self._lock:
            segments, _ = self._model.transcribe(
                audio,
                language="ar",
                beam_size=self.beam_size,
                vad_filter=False,  # the segmenter already did this
                without_timestamps=True,
                # Each chunk stands alone: conditioning on previous text makes
                # Whisper continue the *expected* ayah instead of what was said.
                condition_on_previous_text=False,
            )
            texts = [s.text for s in segments if s.no_speech_prob < self.no_speech_threshold]
        return " ".join(t.strip() for t in texts).strip()


def asr_available() -> bool:
    """True if the optional ASR dependencies are installed (`pip install -e engine[asr]`)."""
    try:
        import av  # noqa: F401
        import faster_whisper  # noqa: F401
    except ImportError:
        return False
    return True
