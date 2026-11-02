"""Speech -> text, behind a one-method protocol.

`WhisperTranscriber` wraps a Whisper model fine-tuned on Quran recitation
(Tarteel's whisper-base-ar-quran, converted for faster-whisper). It is the
laptop baseline; the phone will use the same model exported to ONNX behind the
same protocol (Phase 6).
"""

from __future__ import annotations

import os
import sys
import threading
from dataclasses import dataclass, field
from pathlib import Path
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
    device: str = field(default_factory=lambda: os.environ.get("RAFIQ_ASR_DEVICE", "auto"))  # auto|cuda|cpu
    compute_type: str = "auto"  # int8 on CPU, int8_float16 on GPU
    beam_size: int = 1  # greedy: ~2x faster, and the matcher absorbs the odd error
    no_speech_threshold: float = 0.6  # drop segments Whisper itself thinks are not speech

    def __post_init__(self) -> None:
        self._model = None
        self.active_device: str | None = None  # where the model actually loaded
        self._lock = threading.Lock()  # one decode at a time; the server shares one model

    def load(self) -> None:
        """Load and warm up (downloads ~150 MB on first use). Called lazily by `transcribe`.

        Each call costs ~0.4 s on a laptop CPU *whatever the audio length*:
        Whisper always encodes a 30 s window. Latency therefore comes from how
        often we call it, which is the listener's job to manage.
        """
        with self._lock:
            if self._model is None:
                devices = ["cuda", "cpu"] if self.device == "auto" else [self.device]
                errors = []
                for device in devices:
                    try:
                        self._model = self._load_on(device)
                        self.active_device = device
                        break
                    except Exception as e:  # missing CUDA libraries, no GPU, out of memory...
                        errors.append(f"{device}: {e}")
                else:
                    raise RuntimeError("could not load the ASR model: " + "; ".join(errors))

    def _load_on(self, device: str):
        from faster_whisper import WhisperModel

        if device == "cuda":
            _expose_pip_cuda_libraries()
        compute = self.compute_type
        if compute == "auto":
            compute = "int8_float16" if device == "cuda" else "int8"
        model = WhisperModel(self.model, device=device, compute_type=compute, revision=self.revision)
        # Warm-up: the first decode allocates buffers and takes ~5x longer. Pay
        # it here, at load time, not on the listener's first chunk. It also
        # proves the device really works (CUDA fails on first use, not on load).
        warm, _ = model.transcribe(np.zeros(SAMPLE_RATE, dtype=np.float32), language="ar")
        list(warm)  # transcribe() is lazy: decoding happens when the segments are consumed
        return model

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


def _expose_pip_cuda_libraries() -> None:
    """Make NVIDIA's pip-installed DLLs (nvidia-cublas-cu12, nvidia-cudnn-cu12) findable on Windows.

    On Linux the wheels' rpaths handle this; Windows needs the directories
    registered and on PATH before CTranslate2 loads cuBLAS/cuDNN.
    """
    if sys.platform != "win32":
        return
    try:
        import nvidia
    except ImportError:
        return
    for root in nvidia.__path__:
        for bin_dir in Path(root).glob("*/bin"):
            os.add_dll_directory(str(bin_dir))
            os.environ["PATH"] = str(bin_dir) + os.pathsep + os.environ.get("PATH", "")


def asr_available() -> bool:
    """True if the optional ASR dependencies are installed (`pip install -e engine[asr]`)."""
    try:
        import av  # noqa: F401
        import faster_whisper  # noqa: F401
    except ImportError:
        return False
    return True
