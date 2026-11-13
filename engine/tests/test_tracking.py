from __future__ import annotations

import pytest

from rafiq import evaluation
from rafiq.normalize import tokenize
from rafiq.simulate import NoiseConfig, Step, simulate
from rafiq.tracking import IDLE, LOST, TRACKING, UNCERTAIN, DefaultTransition, Tracker, TrackerConfig


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


# -- evidence: a miss is not doubt -----------------------------------------


def test_a_miss_carries_no_evidence_and_holds_the_position(tracker, vid):
    following = feed(tracker, "والضحى والليل إذا سجى", "ما ودعك ربك وما قلى")[-1]
    assert following.status == TRACKING and following.evidence
    for chunk in ("zzz", "", "الم"):  # noise, silence, a word that fits anywhere
        miss = tracker.update(chunk)
        assert not miss.evidence, chunk
        assert miss.status == UNCERTAIN and miss.confidence == 0.0
        assert (miss.verse_id, miss.word, miss.upcoming_verse) == (
            following.verse_id,
            following.word,
            following.upcoming_verse,
        )
        assert miss.alternatives == following.alternatives and miss.pending_verse == following.pending_verse
        tracker.update("وللآخرة خير لك من الأولى")  # evidence again before the next miss
        assert tracker.state.evidence
        following = tracker.state


def test_misses_in_a_row_are_lost_without_evidence(tracker):
    feed(tracker, "والضحى والليل إذا سجى", "ما ودعك ربك وما قلى")
    states = feed(tracker, *["zzz"] * tracker.config.lost_after)
    assert [s.status for s in states] == [UNCERTAIN] * (tracker.config.lost_after - 1) + [LOST]
    assert not any(s.evidence for s in states)


def test_a_previewed_miss_says_so_and_changes_nothing(tracker):
    feed(tracker, "والضحى والليل إذا سجى")
    before = tracker.state
    preview = tracker.preview("zzz")
    assert not preview.evidence and preview.status == UNCERTAIN
    assert tracker.state is before
    assert tracker.preview("ما ودعك ربك وما قلى").evidence


def test_idle_and_cold_start_misses_have_no_evidence(tracker):
    assert not tracker.state.evidence
    assert not tracker.update("zzz").evidence and tracker.state.status == IDLE


def test_an_exact_tie_is_evidence_with_zero_confidence(tracker):
    """The same words five times in Ash-Shu'ara: confidence 0, like a miss, but
    the chunk did match. Only `evidence` tells genuine doubt from no news."""
    state = tracker.update("فاتقوا الله وأطيعون وما أسألكم عليه من أجر")
    assert state.evidence and state.confidence == 0.0 and state.status == UNCERTAIN
    assert len(state.alternatives) >= 2


def test_competing_hypotheses_are_evidence_of_doubt(tracker, vid):
    feed(tracker, "والضحى والليل إذا سجى", "ما ودعك ربك وما قلى")
    far = tracker.update("الله لا إله إلا هو الحي القيوم")  # Ayat al-Kursi, unconfirmed
    assert far.evidence and far.status == UNCERTAIN and far.pending_verse == vid(2, 255)
    held = tracker.update("zzz")  # no news: the doubt is still the last evidence
    assert not held.evidence and held.pending_verse == vid(2, 255)


def test_the_users_position_is_evidence(tracker, vid):
    assert tracker.set_position(vid(36, 1)).evidence


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


# -- repeated text: an unconfirmed position must be decided by its own text --

REFRAIN = "فبأي آلاء ربكما تكذبان"  # 31 times in Ar-Rahman, 55:13 to 55:77
DUHA = ("والضحى والليل إذا سجى", "ما ودعك ربك وما قلى")


def test_an_exact_tie_nearby_is_not_shown_at_cold_start(tracker, vid):
    """18:89 and 18:92 are the same words, a few ayahs apart: not one place."""
    state = tracker.update("ثم أتبع سببا")
    assert state.verse_id is None and state.confidence == 0.0
    assert state.pending_verse == vid(18, 89) and vid(18, 92) in state.alternatives
    state = tracker.update("حتى إذا بلغ بين السدين وجد من دونهما قوما")  # the words after 18:92
    assert state.verse_id == vid(18, 93)


def test_a_misheard_word_between_two_copies_is_a_tie(tracker, vid):
    state = tracker.update("وإن مع العسر يسرا")  # 94:5 begins فإن, 94:6 إن
    assert state.verse_id is None and {state.pending_verse, *state.alternatives} >= {vid(94, 5), vid(94, 6)}


def test_a_near_tie_is_a_tie(matcher, vid):
    """The refrain, then the next breath with the start of the following one:
    the earliest copies score 0.99 and 0.96. Exact ties alone would show the
    first copy while the imam is at 55:50."""
    chunks = (REFRAIN, "فيهما عينان تجريان فبأي آلاء")  # 55:49, then 55:50 and the start of 55:51
    exact_only = Tracker(matcher, TrackerConfig(tie_margin=0.0))
    assert [exact_only.update(c).verse_id for c in chunks][-1] == vid(55, 18)
    tracker = Tracker(matcher)
    states = [tracker.update(c) for c in chunks]
    top, second = tracker._hyps[0], tracker._hyps[1]
    assert 0 < top.score - second.score <= tracker.config.tie_margin
    assert all(s.verse_id is None for s in states)
    state = tracker.update("فيهما من كل فاكهة زوجان")  # 55:52: distinct words decide
    assert state.verse_id == vid(55, 52)


def test_the_ar_rahman_refrain_names_the_surah_and_waits(tracker, q, vid):
    """The surah is known (every copy is in it), the ayah is not."""
    for _ in range(2):  # two copies confirm nothing
        state = tracker.update(REFRAIN)
        assert state.verse_id is None and state.confidence == 0.0
        assert {q.by_id(v).surah for v in (state.pending_verse, *state.alternatives)} == {55}
    assert tracker.update("يسأله من في السماوات والأرض كل يوم هو في شأن").verse_id == vid(55, 29)


def test_joining_on_a_later_copy_shows_the_right_place_once_it_is_distinct(tracker, vid):
    """Join at the refrain of 55:45 (one of 31), then 55:46."""
    assert tracker.update(REFRAIN).verse_id is None
    assert tracker.update("ولمن خاف مقام ربه جنتان").verse_id == vid(55, 46)


def test_repeated_verses_are_never_shown_at_cold_start(matcher, index, q):
    """Every ayah whose words are another ayah's too (at least 3 words)."""
    by_text: dict[tuple[str, ...], list[int]] = {}
    for v in range(1, len(q) + 1):
        a, b = index.verse_span(v)
        by_text.setdefault(tuple(index.words[a:b]), []).append(v)
    repeated = [t for t, vs in by_text.items() if len(vs) >= 2 and len(t) >= 3]
    assert len(repeated) > 80
    shown = [" ".join(t) for t in repeated if Tracker(matcher).update(" ".join(t)).verse_id is not None]
    assert shown == []


def test_unique_text_is_unchanged_at_cold_start(matcher, index, q):
    """The rule only adds ties: for every 10th ayah whose words fit exactly
    nowhere else (102:3 does not: it is the end of 102:4 too), cold start shows
    exactly what it did without the rule."""
    off = TrackerConfig(tie_margin=-1.0)
    checked = 0
    for v in range(1, len(q) + 1, 10):
        a, b = index.verse_span(v)
        words = index.words[a:b]
        if sum(m.score >= 0.999 for m in matcher.match_tokens(words, k=3)) > 1:
            continue
        new, old = Tracker(matcher).update(" ".join(words)), Tracker(matcher, off).update(" ".join(words))
        assert (new.verse_id, new.status, new.confidence) == (old.verse_id, old.status, old.confidence), v
        checked += 1
    assert checked > 550


def test_a_far_jump_into_repeated_text_waits_for_distinct_words(tracker, vid):
    feed(tracker, *DUHA)
    held = feed(tracker, REFRAIN, REFRAIN)
    # Never a copy of the refrain: the screen holds 93:3, unsure.
    assert all(s.verse_id == vid(93, 3) and s.status == UNCERTAIN for s in held)
    states = feed(tracker, "يسأله من في السماوات والأرض كل يوم هو في شأن", "سنفرغ لكم أيها الثقلان")
    assert states[-1].verse_id == vid(55, 31)


def test_after_lost_and_al_fatiha_repeated_text_still_waits(tracker, q):
    feed(tracker, *DUHA, *["zzz"] * tracker.config.lost_after)
    feed(tracker, "الحمد لله رب العالمين", "الرحمن الرحيم مالك يوم الدين")
    held = feed(tracker, REFRAIN, REFRAIN)
    assert all(s.verse_id is None or q.by_id(s.verse_id).surah != 55 for s in held)


def test_a_far_jump_on_distinct_words_still_confirms_in_two(tracker, vid):
    feed(tracker, *DUHA)
    first = tracker.update("الله لا إله إلا هو الحي القيوم")
    assert first.verse_id == vid(93, 3) and first.pending_verse == vid(2, 255)
    assert tracker.update("لا تأخذه سنة ولا نوم").verse_id == vid(2, 255)


# -- the tie report: repeated text, the full set and whether it is trusted ---


def tie(matcher, text: str):
    return Tracker(matcher).update(text)


def surahs_of(q, verses) -> set[int]:
    return {q.by_id(v).surah for v in verses}


def test_the_refrain_reports_all_31_copies_in_one_surah(matcher, q):
    state = tie(matcher, REFRAIN)
    copies = [v.id for v in q if v.surah == 55 and tokenize(v.text) == tokenize(REFRAIN)]
    assert state.verse_id is None
    assert state.tied == copies and len(copies) == 31
    assert state.tie_trusted
    assert len(state.alternatives) == 3  # the display list is unchanged


@pytest.mark.parametrize(
    ("text", "ayahs"),
    [
        ("ثم أتبع سببا", [(18, 89), (18, 92)]),
        ("ولا أنتم عابدون ما أعبد", [(109, 3), (109, 5)]),
        ("وأذنت لربها وحقت", [(84, 2), (84, 5)]),
        ("وإن مع العسر يسرا", [(94, 5), (94, 6)]),  # a misheard word between two copies
    ],
)
def test_repeated_ayahs_close_by_are_one_trusted_surah(matcher, vid, text, ayahs):
    state = tie(matcher, text)
    assert state.verse_id is None
    assert state.tied == [vid(s, a) for s, a in ayahs]
    assert state.tie_trusted


def test_a_phrase_in_three_surahs_is_a_trusted_tie_across_them(matcher, q):
    state = tie(matcher, "فاتقوا الله وأطيعون")
    assert surahs_of(q, state.tied) == {3, 26, 43}
    assert state.tie_trusted


@pytest.mark.parametrize("text", ["كذلك نجزي المحسنين", "ويل يومئذ للمكذبين", "إن الله غفور رحيم"])
def test_ties_that_would_not_have_been_shown_are_not_trusted(matcher, text):
    """Their surahs taken as one place still fall short of the cold-start
    confidence against the best rival outside them."""
    state = tie(matcher, text)
    assert len(state.tied) >= 2 and not state.tie_trusted


def test_a_phrase_repeated_beyond_retrievals_cap_is_never_trusted(matcher, q):
    """يا أيها الذين آمنوا: 89 copies, 40 shortlisted. As one place it would be
    shown (confidence 0.865), but the set is incomplete: not trusted."""
    state = tie(matcher, "يا أيها الذين آمنوا")
    assert len(state.tied) < 89 and not state.tie_trusted


@pytest.mark.parametrize(
    "text",
    [
        "بلى مربي للقسط",  # a misheard preview of 7:29 (recorded)
        "بما ما ربي",  # recorded, far room
        "ذلك وما",  # two words: weak evidence
    ],
)
def test_garbled_and_short_chunks_are_not_trusted(matcher, text):
    state = tie(matcher, text)
    assert not state.tie_trusted


def test_a_one_word_chunk_is_a_miss_and_reports_no_tie(matcher):
    state = tie(matcher, "الم")
    assert not state.evidence and state.tied == [] and not state.tie_trusted


def test_unique_text_reports_no_tie(matcher):
    state = tie(matcher, "والضحى والليل إذا سجى")
    assert state.verse_id is not None and state.tied == [] and not state.tie_trusted


def test_the_tie_is_held_through_a_miss_and_cleared_on_acceptance(tracker, vid):
    first = tracker.update(REFRAIN)
    held = tracker.update("zzz")
    assert not held.evidence and held.tied == first.tied and held.tie_trusted
    accepted = tracker.update("يسأله من في السماوات والأرض كل يوم هو في شأن")
    assert accepted.verse_id == vid(55, 29) and accepted.tied == [] and not accepted.tie_trusted


def test_the_users_position_clears_the_tie(tracker, vid):
    assert tracker.update(REFRAIN).tied
    state = tracker.set_position(vid(55, 47))
    assert state.tied == [] and not state.tie_trusted


def test_a_far_jump_into_repeated_text_reports_the_tie_while_holding(tracker, q, vid):
    feed(tracker, *DUHA)
    state = tracker.update(REFRAIN)
    assert state.verse_id == vid(93, 3)  # the held position stays
    assert surahs_of(q, state.tied) == {55} and state.tie_trusted


def test_no_tie_is_reported_where_the_screen_already_is(tracker, vid):
    """The refrain right after 55:12: context decides, nothing is unconfirmed."""
    tracker.set_position(vid(55, 12))
    state = tracker.update(REFRAIN)
    assert state.verse_id == vid(55, 13) and state.tied == []


def test_previews_report_ties_and_change_nothing(tracker):
    preview = tracker.preview(REFRAIN)
    assert len(preview.tied) == 31 and tracker.state.tied == []
