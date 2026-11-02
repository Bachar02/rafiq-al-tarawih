"""Audio -> text -> position. Needs the optional extra: `pip install -e "engine[asr]"`.

Only numpy is required to import this package; faster-whisper and PyAV are
imported lazily by the parts that need them, so the segmenter and listener can
be tested (and the server can start) without the model installed.
"""

from rafiq.asr.audio import SAMPLE_RATE, load_audio
from rafiq.asr.listener import Heard, Listener, ListenerConfig
from rafiq.asr.segmenter import Segment, Segmenter, SegmenterConfig
from rafiq.asr.transcriber import Transcriber, WhisperTranscriber, asr_available
from rafiq.asr.vad import EnergyVad, SileroVad, Vad

__all__ = [
    "SAMPLE_RATE",
    "EnergyVad",
    "Heard",
    "Listener",
    "ListenerConfig",
    "Segment",
    "Segmenter",
    "SegmenterConfig",
    "SileroVad",
    "Transcriber",
    "Vad",
    "WhisperTranscriber",
    "asr_available",
    "load_audio",
]
