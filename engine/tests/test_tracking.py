from __future__ import annotations

import pytest

from rafiq import evaluation
from rafiq.simulate import NoiseConfig, Step, simulate
from rafiq.tracking import IDLE, LOST, TRACKING, DefaultTransition, Tracker


@pytest.fixture
def tracker(matcher) -> Tracker:
    return Tracker(matcher)


def feed(tracker: Tracker, *chunks: str):
    return [tracker.update(c) for c in chunks]


# -- transition prior ------------------------------------------------------


def test_transition_prefers_onward_over_back_over_far():
    t = DefaultTransition()
    assert t(100, 101) == 0.0
    assert t(100, 120) > t(100, 60) > t(100, 5000)


# -- tracking behaviour ----------------------------------------------------


def test_follows_a_surah(tracker, vid):
    states = feed(tracker, "والضحى والليل إذا سجى", "ما ودعك ربك وما قلى", "وللآخرة خير لك من الأولى")
    assert [s.verse_id for s in states] == [vid(93, 2), vid(93, 3), vid(93, 4)]
    assert states[-1].status == TRACKING


def test_context_resolves_a_repeated_refrain(tracker, vid):
    """The refrain occurs 31 times; context says which one."""
    feed(tracker, "يخرج منهما اللؤلؤ والمرجان")  # 55:22
    state = tracker.update("فبأي آلاء ربكما تكذبان")
    assert state.verse_id == vid(55, 23)


def test_noise_chunk_does_not_move_the_display(tracker, vid):
    feed(tracker, "الله لا إله إلا هو الحي القيوم", "لا تأخذه سنة ولا نوم له ما في السماوات")
    before = tracker.state.verse_id
    state = tracker.update("يوسف أعرض عن هذا")  # perfectly valid Quran text, from far away
    assert state.verse_id == before


def test_far_jump_needs_confirmation(tracker, vid):
    feed(tracker, "والضحى والليل إذا سجى", "ما ودعك ربك وما قلى")
    first = tracker.update("الله لا إله إلا هو الحي القيوم")
    assert first.verse_id == vid(93, 3) and first.pending_verse == vid(2, 255)
    second = tracker.update("لا تأخذه سنة ولا نوم")
    assert second.verse_id == vid(2, 255)


def test_resumes_after_fatiha(tracker, vid):
    feed(tracker, "قل أعوذ برب الفلق", "من شر ما خلق")  # 113:1-2
    feed(tracker, "الحمد لله رب العالمين", "الرحمن الرحيم مالك يوم الدين", "صراط الذين أنعمت عليهم")
    assert tracker.state.verse_id == vid(1, 7)
    state = tracker.update("ومن شر غاسق إذا وقب")  # back to where he was: 113:3
    assert state.verse_id == vid(113, 3)


def test_seed_biases_ambiguous_start(tracker, vid):
    tracker.seed(vid(55, 30))
    state = tracker.update("فبأي آلاء ربكما تكذبان")
    assert vid(55, 30) <= (state.verse_id or state.pending_verse) <= vid(55, 34)


def test_status_lifecycle(tracker):
    assert tracker.state.status == IDLE
    feed(tracker, "", "")
    assert tracker.state.status == IDLE
    feed(tracker, "والضحى والليل إذا سجى", "ما ودعك ربك وما قلى")
    for _ in range(tracker.config.lost_after):
        tracker.update("zzz")
    assert tracker.state.status == LOST
    tracker.reset()
    assert tracker.state.status == IDLE and tracker.state.verse_id is None


# -- simulator and metrics -------------------------------------------------


def test_clean_simulation_is_the_text(index, vid):
    steps = simulate(index, vid(93, 1), vid(93, 11), NoiseConfig.clean(), seed=0)
    words = " ".join(s.text for s in steps).split()
    assert (
        words
        == index.text(*index.verse_span(1)).split()
        + index.text(index.verse_span(vid(93, 1))[0], index.verse_span(vid(93, 11))[1]).split()
    )  # basmala, then the surah
    assert steps[-1].truth_verse == vid(93, 11)


def test_simulation_is_deterministic(index, vid):
    a = simulate(index, vid(2, 1), vid(2, 20), seed=5)
    b = simulate(index, vid(2, 1), vid(2, 20), seed=5)
    assert a == b


def test_score_counts_wrong_jumps_and_recovery():
    steps = [Step("x", v, 0, (v,)) for v in (10, 11, 12, 13)]
    report = evaluation.score([10, 500, 12, 13], steps)
    assert report.wrong_jumps == 1
    assert report.acceptable == 0.75
    assert report.mean_recovery == 1.0
    assert not report.unrecovered


def test_end_to_end_on_noisy_stream(tracker, index, vid):
    steps = simulate(index, vid(18, 1), vid(18, 30), NoiseConfig.preset("light"), seed=2)
    _, report = evaluation.run(tracker, steps)
    assert report.acceptable >= 0.95
    assert report.wrong_jumps == 0
