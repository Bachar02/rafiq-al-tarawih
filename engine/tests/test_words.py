"""The word tracker: follows the imam word by word from a stream of letters."""

from __future__ import annotations

import pytest

from rafiq.matching import get_index
from rafiq.word_sim import LetterNoise, run, simulate_letters
from rafiq.words import IDLE, LOST, TRACKING, UNCERTAIN, WordTracker


@pytest.fixture(scope="module")
def index():
    return get_index()


def recite(tracker: WordTracker, index, positions) -> list[tuple[int, object]]:
    """Feed the words at `positions`, letter by letter; (truth, state) per letter."""
    out = []
    for p in positions:
        for ch in index.words[p]:
            out.append((p, tracker.feed(ch)))
    return out


def test_idle_until_anchored(index):
    tracker = WordTracker(index)
    assert tracker.feed("بسم الله").status == IDLE
    assert tracker.anchor(100).status == UNCERTAIN
    assert tracker.state.word is None


def test_follows_clean_recitation_word_by_word(index):
    tracker = WordTracker(index)
    lo, hi = index.verse_span(2050)  # a long ayah, anchored at its start
    tracker.anchor(lo)
    trace = recite(tracker, index, range(lo, hi + 20))
    shown = [(truth, st.word) for truth, st in trace if st.status == TRACKING]
    assert len(shown) > 0.8 * len(trace)
    assert all(abs(word - truth) <= 1 for truth, word in shown)
    assert trace[-1][1].word == hi + 19
    assert trace[-1][1].confidence > 0.9


def test_finds_the_imam_ahead_of_a_late_anchor(index):
    tracker = WordTracker(index)
    lo, _ = index.verse_span(3000)
    tracker.anchor(lo)
    trace = recite(tracker, index, range(lo + 8, lo + 20))  # he was already 8 words on
    assert trace[-1][1].status == TRACKING
    assert trace[-1][1].word == lo + 19


def test_follows_the_imam_back_when_he_repeats(index):
    tracker = WordTracker(index)
    lo, _ = index.verse_span(2050)
    tracker.anchor(lo)
    recite(tracker, index, range(lo, lo + 12))
    trace = recite(tracker, index, range(lo + 7, lo + 12))  # back five words
    assert trace[-1][1].status == TRACKING
    assert trace[-1][1].word == lo + 11
    # While going back, a far word was highlighted for one letter at most: his
    # first "ا" also fits the alef of the word he would have said next.
    wrong = [truth for truth, st in trace if st.status == TRACKING and abs(st.word - truth) > 2]
    assert len(wrong) <= 1


def test_the_basmala_is_followed_when_recited_and_skipped_when_not(index):
    quran = index.quran
    first = quran.surah(113).first_verse_id  # al-Falaq follows al-Ikhlas
    start, _ = index.verse_span(first)
    basmala = index.verse_span(1)
    for aloud in (True, False):
        tracker = WordTracker(index)
        tracker.anchor(start - 6)
        recite(tracker, index, range(start - 6, start))
        seen = []
        if aloud:
            for p in range(*basmala):
                for ch in index.words[p]:
                    seen.append(tracker.feed(ch).basmala)
            assert first in seen, "the basmala before al-Falaq is reported"
        trace = recite(tracker, index, range(start, start + 4))
        assert trace[-1][1].status == TRACKING
        assert trace[-1][1].word == start + 3
        assert trace[-1][1].basmala is None


def test_stops_highlighting_when_the_imam_leaves_the_text(index):
    tracker = WordTracker(index)
    lo, _ = index.verse_span(4000)
    tracker.anchor(lo)
    recite(tracker, index, range(lo, lo + 10))
    assert tracker.state.status == TRACKING
    elsewhere = index.verse_span(200)[0]  # far away: outside the window
    trace = recite(tracker, index, range(elsewhere, elsewhere + 12))
    statuses = [st.status for _, st in trace]
    assert TRACKING not in statuses[8:], "unsure within a word"
    assert statuses[-1] == LOST
    assert trace[-1][1].word is None


def test_al_fatiha_ends_its_own_window(index):
    tracker = WordTracker(index)
    tracker.anchor(0)
    end = index.verse_span(7)[1]
    recite(tracker, index, range(0, end))
    assert tracker.state.word == end - 1
    # "amin", then the imam's surah: not al-Baqarah 2:1 "الم", which follows in the text.
    states = [tracker.feed(ch) for ch in "امين"] + [tracker.feed(ch) for ch in "الم"]
    assert all(st.status != TRACKING for st in states[1:])


def test_after_a_long_pause_a_highlight_needs_fresh_letters(index):
    tracker = WordTracker(index)
    lo, _ = index.verse_span(5000)
    tracker.anchor(lo)
    recite(tracker, index, range(lo, lo + 8))
    assert tracker.state.status == TRACKING
    assert tracker.pause().status == UNCERTAIN
    trace = recite(tracker, index, range(lo + 8, lo + 12))
    statuses = [st.status for _, st in trace]
    n = tracker.config.confirm
    assert statuses[: n - 1] == [UNCERTAIN] * (n - 1), "the first letters only confirm"
    assert statuses[n - 1] == TRACKING
    assert statuses[-1] == TRACKING


def test_tokens_may_be_words_or_subwords_with_diacritics(index):
    lo, _ = index.verse_span(2050)
    by_letter, by_token = WordTracker(index), WordTracker(index)
    by_letter.anchor(lo)
    by_token.anchor(lo)
    recite(by_letter, index, range(lo, lo + 6))
    # Same letters, cut differently and in model spelling: same position.
    for p in range(lo, lo + 6):
        by_token.feed([f"▁{index.words[p][:2]}ُ", index.words[p][2:]])
    assert by_token.state == by_letter.state


def test_simulated_recitation_is_followed_and_rarely_wrong(index):
    letters = simulate_letters(index, 1500, 1510, LetterNoise.preset("light"), seed=3)
    _, report = run(WordTracker(index), letters)
    assert report.shown > 0.7
    assert report.near > 0.95
    assert report.wrong < 0.02


def test_a_model_that_hears_little_stays_quiet(index):
    letters = simulate_letters(index, 1500, 1510, LetterNoise.preset("broken"), seed=3)
    _, report = run(WordTracker(index), letters)
    assert report.shown < 0.3
    assert report.wrong < 0.03
