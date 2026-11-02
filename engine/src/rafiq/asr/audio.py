"""Audio I/O. Everything inside the engine is 16 kHz mono float32 in [-1, 1]."""

from __future__ import annotations

from pathlib import Path

import numpy as np

SAMPLE_RATE = 16_000


def load_audio(path: str | Path, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Decode any audio/video file PyAV understands into mono float32 samples.

    Written against PyAV directly rather than faster-whisper's helper, which
    breaks on current PyAV releases.
    """
    import av

    chunks: list[np.ndarray] = []
    with av.open(str(path)) as container:
        resampler = av.AudioResampler(format="s16", layout="mono", rate=sample_rate)
        for frame in container.decode(audio=0):
            chunks.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(frame))
        chunks.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(None))
    if not chunks:
        return np.zeros(0, dtype=np.float32)
    return np.concatenate(chunks).astype(np.float32) / 32768.0
