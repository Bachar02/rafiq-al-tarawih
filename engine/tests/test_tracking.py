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


def test_detects_surah_and_ayah_with_no_help(tracker, vid):
    """The core feature: no hint, joined mid-surah, anywhere in the Quran."""
    state = tracker.update("قالوا يا موسى إما أن تلقي وإما أن نكون نحن الملقين")
    assert state.verse_id == vid(7, 115)


def test_hint_resolves_an_ambiguous_start(tracker, q, vid):
    s = q.surah(55)
    tracker.hint(s.first_verse_id, s.last_verse_id)
    feed(tracker, "فبأي آلاء ربكما تكذبان", "فبأي آلاء ربكما تكذبان")
    pos = tracker.state.verse_id or tracker.state.pending_verse
    assert q.by_id(pos).surah == 55


def test_wrong_hint_does_not_trap(tracker, q, vid):
    s = q.surah(2)
    tracker.hint(s.first_verse_id, s.last_verse_id)  # the user is wrong: it is Ad-Duha
    feed(tracker, "والضحى والليل إذا سجى", "ما ودعك ربك وما قلى", "وللآخرة خير لك من الأولى")
    assert tracker.state.verse_id == vid(93, 4)


def test_hint_survives_reset_and_can_be_cleared(tracker, q):
    tracker.hint(*q.juz_span(30))
    tracker.reset()
    assert tracker._hint is not None
    tracker.hint(None)
    assert tracker._hint is None


def test_ambiguous_refrain_reports_alternatives(tracker):
    state = tracker.update("فاتقوا الله وأطيعون وما أسألكم عليه من أجر")  # five times in Ash-Shu'ara
    assert len(state.alternatives) >= 2


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


def test_skip_words_joins_mid_ayah(index, vid):
    full = simulate(index, vid(93, 1), vid(93, 3), NoiseConfig.clean(), seed=0)
    late = simulate(index, vid(93, 1), vid(93, 3), NoiseConfig.clean(), seed=0, skip_words=5)
    assert " ".join(s.text for s in full).split()[5:] == " ".join(s.text for s in late).split()


def test_time_to_lock():
    steps = [Step("x", v, 0, (v,)) for v in (10, 11, 12)]
    report = evaluation.score([None, 11, 12], steps)
    assert report.time_to_lock == 2 and not report.first_shown_wrong
    report = evaluation.score([500, 500, 12], steps)
    assert report.time_to_lock == 3 and report.first_shown_wrong


def test_end_to_end_on_noisy_stream(tracker, index, vid):
    steps = simulate(index, vid(18, 1), vid(18, 30), NoiseConfig.preset("light"), seed=2)
    _, report = evaluation.run(tracker, steps)
    assert report.acceptable >= 0.95
    assert report.wrong_jumps == 0


# -- user control: lock the surah, "the imam is here" ------------------------


def test_lock_keeps_the_tracker_in_the_surah(tracker, q, vid):
    """The refrain exists 31 times in Ar-Rahman but also resembles text elsewhere;
    locked to surah 55, nothing outside it can ever be shown."""
    s = q.surah(55)
    tracker.lock(s.first_verse_id, s.last_verse_id)
    for chunk in ["فبأي آلاء ربكما تكذبان", "الله لا إله إلا هو الحي القيوم", "لا تأخذه سنة ولا نوم"]:
        state = tracker.update(chunk)
        shown = state.verse_id or state.pending_verse
        assert shown is None or q.by_id(shown).surah == 55
    assert tracker.locked == (s.first_verse_id, s.last_verse_id)


def test_lock_still_allows_fatiha(tracker, q, vid):
    s = q.surah(113)
    tracker.lock(s.first_verse_id, s.last_verse_id)
    for chunk in [
        "قل أعوذ برب الفلق",
        "من شر ما خلق",
        "الحمد لله رب العالمين",
        "الرحمن الرحيم مالك يوم الدين",
    ]:
        state = tracker.update(chunk)
    assert state.verse_id == vid(1, 4)


def test_lock_survives_reset_and_unlocks(tracker, q):
    s = q.surah(2)
    tracker.lock(s.first_verse_id, s.last_verse_id)
    tracker.reset()
    assert tracker.locked is not None
    tracker.lock(None)
    assert tracker.locked is None


def test_set_position_shows_it_and_continues_from_there(tracker, vid):
    feed(tracker, "قل أعوذ برب الفلق")  # tracker somewhere else entirely
    state = tracker.set_position(vid(93, 4))
    assert state.verse_id == vid(93, 4) and state.status == TRACKING
    state = tracker.update("ولسوف يعطيك ربك فترضى")  # the imam continues: 93:5
    assert state.verse_id == vid(93, 5)


def test_set_position_beats_an_ambiguous_refrain(tracker, vid):
    tracker.set_position(vid(55, 40))
    state = tracker.update("فبأي آلاء ربكما تكذبان")  # 55:40 is itself a refrain ayah
    assert vid(55, 40) <= state.verse_id <= vid(55, 42)
