"""Audio pipeline. Segmenter and listener use synthetic audio and a fake
transcriber, so they run anywhere. The real-model test runs only when the ASR
extra is installed and a sample recording has been downloaded."""

from __future__ import annotations

from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

from rafiq.asr import SAMPLE_RATE, EnergyVad, Listener, ListenerConfig, Segmenter, asr_available  # noqa: E402
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


def test_one_big_block_with_two_breaths_gives_two_chunks():
    """A caller that fell behind feeds everything at once; breaths must stay separate."""
    seg = Segmenter(EnergyVad())
    audio = np.concatenate([tone(2.0), silence(0.6), tone(2.0), silence(0.6)])
    segs = seg.push(audio) + seg.flush()
    assert len(segs) == 2


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
    finals_only = ListenerConfig(partial_every_s=0)
    listener = Listener(Segmenter(EnergyVad()), ScriptedTranscriber(script), Tracker(matcher), finals_only)
    audio = np.concatenate([tone(2.0), silence(0.6), tone(2.0), silence(0.6)])
    heard = []
    for i in range(0, len(audio), 4000):
        heard += listener.feed(audio[i : i + 4000])
    heard += listener.flush()
    assert [h.text for h in heard] == script
    assert heard[-1].state.verse_id == vid(93, 3)
    assert heard[0].start < heard[0].end <= heard[1].start


class ConstantTranscriber:
    def __init__(self, text: str) -> None:
        self.text = text

    def transcribe(self, audio):
        return self.text


def test_partials_preview_without_committing(matcher, vid):
    tracker = Tracker(matcher)
    listener = Listener(Segmenter(EnergyVad()), ConstantTranscriber("والضحى والليل إذا سجى"), tracker)
    heard = []
    for block in np.split(np.concatenate([tone(3.0), silence(0.5)]), 14):
        heard += listener.feed(block)
    partials = [h for h in heard if not h.final]
    assert len(partials) >= 3
    assert partials[0].state.verse_id == vid(93, 2)  # shown mid-breath...
    assert partials[0].end < 1.5  # ...within ~1 s, long before the pause
    assert heard[-1].final  # and committed once at the pause


def test_upcoming_ayah_when_one_ends(matcher, vid):
    tracker = Tracker(matcher)
    tracker.update("ما ودعك ربك وما قلى")  # 93:3 recited to its last word
    state = tracker.update("وللآخرة خير لك من الأولى")  # 93:4, complete
    assert state.verse_id == vid(93, 4) and state.upcoming_verse == vid(93, 5)
    assert state.showing == vid(93, 5)
    mid = tracker.update("ولسوف يعطيك")  # 93:5, not finished
    assert mid.upcoming_verse is None and mid.showing == vid(93, 5)


def test_upcoming_after_fatiha_is_where_the_imam_left_off(matcher, vid):
    tracker = Tracker(matcher)
    chunks = [
        "قل أعوذ برب الفلق",
        "من شر ما خلق",
        "الحمد لله رب العالمين",
        "الرحمن الرحيم مالك يوم الدين",
        "إياك نعبد وإياك نستعين اهدنا الصراط المستقيم",
        "صراط الذين أنعمت عليهم غير المغضوب عليهم ولا الضالين",
    ]
    for chunk in chunks:
        state = tracker.update(chunk)
    assert state.verse_id == vid(1, 7)
    assert state.upcoming_verse == vid(113, 3)


# -- the real model (optional) -----------------------------------------------

SAMPLE = Path(__file__).resolve().parents[2] / "eval" / "audio" / "Alafasy_128kbps" / "093002.mp3"


@pytest.mark.skipif(not asr_available() or not SAMPLE.exists(), reason="needs engine[asr] and eval audio")
def test_whisper_transcribes_a_real_ayah(matcher, vid):
    from rafiq.asr import WhisperTranscriber, load_audio

    text = WhisperTranscriber().transcribe(load_audio(SAMPLE))
    assert matcher.match(text)[0].verse_id == vid(93, 2)


# -- long sessions -------------------------------------------------------------


def test_skip_keeps_timestamps_continuous():
    seg = Segmenter(EnergyVad())
    seg.push(tone(1.0))
    seg.skip(10 * SAMPLE_RATE)  # dropped 10 s of backlog
    out = seg.push(np.concatenate([tone(2.0), silence(0.6)])) + seg.flush()
    assert len(out) == 1 and 11.0 <= out[0].start < 11.2


def test_ten_minute_session_stays_bounded(matcher):
    """A Taraweeh session is long: buffers and timestamps must not drift or grow."""
    listener = Listener(
        Segmenter(EnergyVad()), ConstantTranscriber("والضحى والليل إذا سجى"), Tracker(matcher),
        ListenerConfig(partial_every_s=0),
    )  # fmt: skip
    breath = np.concatenate([tone(3.0), silence(0.7)])  # 3.7 s
    finals, peak_buffer = [], 0
    for _ in range(162):  # ~10 minutes
        for block in np.split(breath, 37):  # 100 ms blocks, like a microphone
            finals += listener.feed(block)
            peak_buffer = max(peak_buffer, len(listener.segmenter._buf))
    assert len(finals) >= 160
    assert peak_buffer < 7 * SAMPLE_RATE
    assert all(a.end <= b.start + 0.25 for a, b in zip(finals, finals[1:], strict=False))
    assert abs(finals[-1].end - 162 * 3.7) < 1.0
