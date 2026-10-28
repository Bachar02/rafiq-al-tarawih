from __future__ import annotations

import random

import pytest

from rafiq.matching import AlignConfig, align
from rafiq.normalize import tokenize

# -- index -----------------------------------------------------------------


def test_stream_covers_every_verse_in_order(index, q):
    assert len(index) == sum(len(tokenize(v.text)) for v in q)
    for verse in (q.verse(1, 1), q.verse(93, 2), q.verse(114, 6)):
        start, end = index.verse_span(verse.id)
        assert index.text(start, end) == " ".join(tokenize(verse.text))
        assert {index.verse_at(p) for p in range(start, end)} == {verse.id}


def test_rare_words_weigh_more(index):
    assert index.idf["القيوم"] > index.idf["الله"]


# -- alignment -------------------------------------------------------------


def test_exact_alignment_finds_span():
    a = align(["ب", "ج"], ["ا", "ب", "ج", "د"])
    assert (a.start, a.end, a.score) == (1, 3, 2.0)


def test_alignment_tolerates_a_dropped_word():
    window = ["والضحي", "والليل", "اذا", "سجي", "ما", "ودعك"]
    a = align(["والضحي", "اذا", "سجي"], window)
    assert (a.start, a.end) == (0, 4)
    assert a.score == pytest.approx(3 - AlignConfig().gap)


def test_alignment_of_unrelated_text_is_zero():
    assert align(["كتاب"], ["سماء", "ارض"]).score == 0.0


# -- matcher ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "ref"),
    [
        ("والضحى والليل إذا سجى", (93, 2)),
        ("الله لا إله إلا هو الحي القيوم لا تأخذه سنة", (2, 255)),
        ("قل هو الله أحد", (112, 1)),
        ("ذلك الكتاب لا ريب فيه", (2, 2)),
    ],
)
def test_matches_exact_text(matcher, vid, text, ref):
    best = matcher.match(text)[0]
    assert best.verse_id == vid(*ref)
    assert best.score == pytest.approx(1.0)


def test_match_crosses_ayah_boundary(matcher, vid):
    best = matcher.match("خير لك من الأولى ولسوف يعطيك ربك")[0]
    assert (best.first_verse, best.last_verse) == (vid(93, 4), vid(93, 5))
    assert best.verse_id == vid(93, 5)  # where the reciter is now


def test_survives_asr_misspellings(matcher, vid):
    # ذ->د, ظ->ض, a dropped word, a spurious word.
    best = matcher.match("دلك الكتاب ريب فيه هدى للمتقين الضين")[0]
    assert best.verse_id in (vid(2, 2), vid(2, 3))


def test_repeated_ayahs_are_all_candidates(matcher, vid):
    refs = {m.verse_id for m in matcher.match("فبأي آلاء ربكما تكذبان", k=10)}
    assert {vid(55, 13), vid(55, 16), vid(55, 18)} <= refs


def test_candidates_do_not_overlap(matcher):
    ms = matcher.match("إن الله غفور رحيم", k=10)
    for i, a in enumerate(ms):
        for b in ms[i + 1 :]:
            assert a.end <= b.start or b.end <= a.start


def test_range_restriction(matcher, index, vid):
    lo, _ = index.verse_span(vid(55, 20))
    hi = index.verse_span(vid(55, 40))[1]
    for m in matcher.match("فبأي آلاء ربكما تكذبان", k=10, lo=lo, hi=hi):
        assert vid(55, 20) <= m.verse_id <= vid(55, 40)


def test_empty_and_garbage_queries(matcher):
    assert matcher.match("") == []
    assert matcher.match("hello 123") == []


def test_random_fragments_are_found(matcher, index):
    """Recall on clean fragments from anywhere in the Quran."""
    rng = random.Random(3)
    hits, n = 0, 200
    for _ in range(n):
        size = rng.randint(4, 8)
        start = rng.randrange(len(index) - size)
        best = matcher.match(index.text(start, start + size), k=5)
        hits += any(m.start <= start and start + size <= m.end for m in best)
    assert hits / n >= 0.98
