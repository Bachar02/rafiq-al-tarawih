"""Scoring the word tracker on recorded speech-model output (rafiq.word_eval)."""

from __future__ import annotations

import pytest

from rafiq.matching import Matcher, get_index
from rafiq.word_eval import Shown, replay_words, score_words, word_truth


@pytest.fixture(scope="module")
def matcher():
    return Matcher(get_index())


def recording(index, verses, chunk=6, revise=False, gap=0.5):
    """A made-up recording: each `chunk` words are a breath, ~0.4 s a word.

    Each breath has partials of its growing prefix (with `revise`, the first
    one is misheard, as Whisper's often is) and a final with the whole chunk.
    The timeline is exact for these times.
    """
    words = [p for v in verses for p in range(*index.verse_span(v))]
    per_word = 0.4
    timeline, t = [], 0.0
    for v in verses:
        lo, hi = index.verse_span(v)
        timeline.append([t, t + (hi - lo) * per_word, v])
        t += (hi - lo) * per_word
    events, k = [], 0
    while k < len(words):
        part = words[k : k + chunk]
        start, end = k * per_word, (k + len(part)) * per_word
        for n in range(1, len(part)):
            text = " ".join(index.words[p] for p in part[:n])
            if revise and n == 1:
                text = "ترره بعيد"
            events.append({"text": text, "start": start, "end": start + n * per_word, "asr_ms": 300,
                           "final": False, "ready": start + n * per_word + 0.3})  # fmt: skip
        events.append({"text": " ".join(index.words[p] for p in part), "start": start, "end": end,
                       "asr_ms": 400, "final": True, "ready": end + 0.4})  # fmt: skip
        k += chunk
    return {"join": 0.0, "seconds": t, "timeline": timeline, "events": events, "room": "made-up"}


def test_word_times_are_shared_out_by_letter_count(matcher):
    index = matcher.index
    rows = word_truth(index, [[10.0, 20.0, 2050], [20.5, 22.0, 1], [22.5, 30.0, 2051]])
    lo, hi = index.verse_span(2050)
    words = rows[0].words
    assert [p for _, _, p in words] == list(range(lo, hi))
    assert words[0][0] == 10.0 and words[-1][1] == pytest.approx(20.0)
    sizes = [len(index.words[p]) for p in range(lo, hi)]
    longest = max(range(len(sizes)), key=sizes.__getitem__)
    assert words[longest][1] - words[longest][0] == pytest.approx(10.0 * sizes[longest] / sum(sizes))
    assert rows[1].words == (), "a basmala before a surah is not scored word by word"
    fatiha = word_truth(index, [[0.0, 3.0, 1], [3.5, 6.0, 2]])
    assert fatiha[0].words, "al-Fatiha 1:1 followed by 1:2 is scored"


def test_real_style_partials_are_followed_without_counting_twice(matcher):
    index = matcher.index
    verses = [2050, 2051, 2052]
    clean = recording(index, verses)
    shown = replay_words(clean, matcher)
    finals = [s for s, e in zip(shown, clean["events"], strict=True) if e["final"]]
    lit = [s.word for s in finals if s.word is not None]
    assert lit, "words are highlighted once the ayah tracker has anchored the word tracker"
    assert lit == sorted(lit), "the highlight only moves on"
    # A misheard first partial in every breath changes nothing once the final is in:
    # each partial starts again from the breath's snapshot.
    revised = replay_words(recording(index, verses, revise=True), matcher)
    revised_finals = [s for s, e in zip(revised, recording(index, verses, revise=True)["events"], strict=True)
                      if e["final"]]  # fmt: skip
    assert [s.word for s in revised_finals] == [s.word for s in finals]


def test_finals_only_uses_the_finals_alone(matcher):
    index = matcher.index
    rec = recording(index, [2050, 2051])
    shown = replay_words(rec, matcher, finals_only=True)
    assert len(shown) == sum(e["final"] for e in rec["events"])


def test_scores_exact_ayah_and_approximate_word_metrics(matcher):
    index = matcher.index
    rec = {"join": 0.0, "seconds": 10.0, "timeline": [[0.0, 10.0, 2050]], "events": []}
    rows = word_truth(index, rec["timeline"])
    # A perfect screen: every word highlighted from the moment it starts.
    perfect = [Shown(a, p, 2050) for a, _, p in rows[0].words]
    r = score_words(perfect, rec, index)
    assert r.coverage == pytest.approx(1.0, abs=0.02)
    assert r.ayah_same == 1.0 and r.ayah_wrong == 0.0
    assert r.word_near == 1.0 and r.useful == pytest.approx(1.0, abs=0.02)
    assert r.word_delay_median == pytest.approx(0.0, abs=0.11)
    # The same, but for 2 s in the middle a word of an ayah far away is highlighted.
    far = index.verse_span(300)[0]
    bad = [s for s in perfect if s.at < 4.0] + [Shown(4.0, far, 2050)]
    bad += [s for s in perfect if s.at >= 6.0]
    r = score_words(bad, rec, index)
    assert r.ayah_wrong == pytest.approx(0.2, abs=0.03)
    assert r.ayah_wrong_per_hour == pytest.approx(3600 / 10.0)
    assert r.recovery_median is not None and r.recovery_median <= 2.1
    # Nothing highlighted at all.
    r = score_words([], rec, index)
    assert r.coverage == 0.0 and r.first_s is None and r.useful == 0.0
