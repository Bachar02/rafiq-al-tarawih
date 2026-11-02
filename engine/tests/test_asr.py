"""Audio pipeline. Segmenter and listener use synthetic audio and a fake
transcriber, so they run anywhere. The real-model test runs only when the ASR
extra is installed and a sample recording has been downloaded."""

from __future__ import annotations

from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

from rafiq.asr import SAMPLE_RATE, EnergyVad, Listener, Segmenter, asr_available  # noqa: E402
from rafiq.tracking import Tracker  # noqa: E402


def tone(seconds: float, amp: float = 0.3) -> np.ndarray:
    t = np.arange(int(seconds * SAMPLE_RATE)) / SAMPLE_RATE
    return (amp * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


def silence(seconds: float, noise: float = 0.0) -> np.ndarray:
    rng = np.random.default_rng(0)
    return (noise * rng.standard_normal(int(seconds * SAMPLE_RATE))).astype(np.float32)


def stream(segmenter: Segmenter, audio: np.ndarray, block: float = 0.25):
    n = int(block * SAMPLE_RATE)
    out = []
    for i in range(0, len(audio), n):
        out += segmenter.push(audio[i : i + n])
    return out + segmenter.flush()


# -- VAD ---------------------------------------------------------------------


def test_energy_vad_finds_tone_spans():
    audio = np.concatenate([silence(0.5), tone(1.0), silence(0.5), tone(0.5)])
    spans = EnergyVad().speech_spans(audio)
    assert len(spans) == 2
    assert abs(spans[0][0] / SAMPLE_RATE - 0.5) < 0.05 and abs(spans[0][1] / SAMPLE_RATE - 1.5) < 0.05


def test_energy_vad_adapts_to_room_noise():
    """In a humming room the floor rises, so hum is silence but the imam is not."""
    vad = EnergyVad()
    audio = np.concatenate([silence(1.0, noise=0.02), tone(1.0), silence(1.0, noise=0.02)])
    spans = vad.speech_spans(audio)
    assert len(spans) == 1
    assert vad.threshold() > 0.02


# -- segmenter ---------------------------------------------------------------


def test_cuts_at_pauses():
    audio = np.concatenate([silence(0.3), tone(2.0), silence(0.6), tone(1.5), silence(0.6)])
    segs = stream(Segmenter(EnergyVad()), audio)
    assert len(segs) == 2
    assert segs[0].start < 0.3 < 2.3 < segs[0].end < 2.6
    assert segs[1].start < 2.9 < 4.4 < segs[1].end


def test_short_speech_waits_to_merge_unless_isolated():
    # 0.6 s then a short pause then more speech: one chunk, not two.
    merged = stream(
        Segmenter(EnergyVad()), np.concatenate([tone(0.6), silence(0.4), tone(1.2), silence(1.2)])
    )
    assert len(merged) == 1
    # 0.6 s followed by a long pause (a short ayah): emitted on its own.
    alone = stream(Segmenter(EnergyVad()), np.concatenate([tone(0.6), silence(1.5)]))
    assert len(alone) == 1


def test_long_speech_is_cut_at_max_length():
    segs = stream(Segmenter(EnergyVad()), np.concatenate([tone(16.0), silence(0.6)]))
    assert len(segs) >= 3
    assert all(s.end - s.start <= 7.5 for s in segs)


def test_blips_are_dropped():
    assert stream(Segmenter(EnergyVad()), np.concatenate([tone(0.1), silence(2.0)])) == []


def test_silence_does_not_grow_the_buffer():
    seg = Segmenter(EnergyVad())
    stream(seg, silence(30.0, noise=0.001))
    assert len(seg._buf) < SAMPLE_RATE


# -- listener ----------------------------------------------------------------


class ScriptedTranscriber:
    """Returns the next line of a script for each chunk, like a perfect ASR."""

    def __init__(self, lines: list[str]) -> None:
        self.lines = list(lines)

    def transcribe(self, audio):
        return self.lines.pop(0) if self.lines else ""


def test_listener_detects_from_audio_chunks(matcher, vid):
    script = ["والضحى والليل إذا سجى", "ما ودعك ربك وما قلى"]
    listener = Listener(Segmenter(EnergyVad()), ScriptedTranscriber(script), Tracker(matcher))
    audio = np.concatenate([tone(2.0), silence(0.6), tone(2.0), silence(0.6)])
    heard = []
    for i in range(0, len(audio), 4000):
        heard += listener.feed(audio[i : i + 4000])
    heard += listener.flush()
    assert [h.text for h in heard] == script
    assert heard[-1].state.verse_id == vid(93, 3)
    assert heard[0].start < heard[0].end <= heard[1].start


# -- the real model (optional) -----------------------------------------------

SAMPLE = Path(__file__).resolve().parents[2] / "eval" / "audio" / "Alafasy_128kbps" / "093002.mp3"


@pytest.mark.skipif(not asr_available() or not SAMPLE.exists(), reason="needs engine[asr] and eval audio")
def test_whisper_transcribes_a_real_ayah(matcher, vid):
    from rafiq.asr import WhisperTranscriber, load_audio

    text = WhisperTranscriber().transcribe(load_audio(SAMPLE))
    assert matcher.match(text)[0].verse_id == vid(93, 2)
