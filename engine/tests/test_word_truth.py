"""Exact word timings (quran-align) mapped onto Rafiq's word stream (rafiq.word_truth).

These use only data in the repository: the downloaded timings are not in git.
"""

from __future__ import annotations

import pytest

from rafiq.matching import get_index
from rafiq.word_eval import Shown, exact_truth, score_words, truth_points, word_truth
from rafiq.word_truth import load_segments, map_verse, map_words, uthmani_words, word_times


@pytest.fixture(scope="module")
def index():
    return get_index()


def test_quran_align_words_are_uthmani_without_pause_marks(index):
    q = index.quran
    assert len(uthmani_words(q.verse(2, 2).text_uthmani)) == 7, "two ۛ marks are not words"
    assert len(uthmani_words(q.verse(1, 1).text_uthmani)) == 4


def test_every_ayah_maps_onto_our_words(index):
    maps = map_words(index)
    assert sum(m.ok for m in maps.values()) / len(maps) >= 0.99
    q = index.quran
    lo, _ = index.verse_span(q.verse(2, 21).id)
    first = maps[q.verse(2, 21).id].groups[0]
    assert first == ((0,), (lo, lo + 1)), "Uthmani يٰٓأَيُّهَا is our two words يا ايها"


def test_a_mapping_that_does_not_fit_is_refused():
    assert not map_verse(["كتب"], ["الرحمن", "الرحيم"], 0).ok


def test_word_times_share_segments_and_skip_untimed_words(index):
    q = index.quran
    v = q.verse(2, 21)  # its first Uthmani word is two of ours
    lo, hi = index.verse_span(v.id)
    wmap = map_words(index)[v.id]
    times = word_times([[0, 1, 0, 1000], [1, 3, 1000, 3000]], wmap, index)
    assert [p for _, _, p in times] == [lo, lo + 1, lo + 2, lo + 3]
    (a0, b0, _), (a1, b1, _) = times[0], times[1]
    assert a0 == 0.0 and b1 == pytest.approx(1.0) and b0 == pytest.approx(a1)
    # يا (2 letters) and ايها (4 letters) share the first second by letters.
    assert b0 == pytest.approx(2 / 6)
    assert times[-1][1] == pytest.approx(3.0)
    assert len(times) < hi - lo, "words the aligner left out have no timing"


def test_the_crash_log_in_one_published_file_is_skipped(tmp_path):
    f = tmp_path / "x.json"
    f.write_text(
        "\nCrashed Command '['./align', ...]'\n"
        '[{"surah": 1, "ayah": 1, "segments": [[0, 1, 60, 610]], "stats": {}},'
        ' {"surah": 12, "ayah": 76, "stats": {"deletions": 33}}]\n',
        encoding="utf-8",
    )
    segs = load_segments(f)
    assert segs[(1, 1)] == [[0, 1, 60, 610]]
    assert segs[(12, 76)] == [], "an ayah the aligner could not time"


def test_exact_and_interpolated_truth_are_scored_at_the_same_moments(index):
    q = index.quran
    v = q.verse(2, 21)
    maps = map_words(index)
    segs = {(2, 21): [[k, k + 1, 1000 * k, 1000 * k + 900] for k in range(len(maps[v.id].groups))]}
    timeline = [[0.0, 20.0, v.id]]
    rec = {"join": 0.0, "seconds": 20.0, "timeline": timeline, "events": []}
    exact = exact_truth(index, timeline, segs, maps)
    points = truth_points(exact, rec)
    assert points and all(k * 0.1 % 1.0 < 0.9 + 1e-9 for k in points), (
        "the 0.1 s gaps between words are left out"
    )
    assert not truth_points(exact_truth(index, timeline, segs, maps, frozenset({"2:21"})), rec)
    perfect = [Shown(a, p, v.id) for a, _, p in exact[0].words]
    r_exact = score_words(perfect, rec, index, rows=exact, points=points)
    r_interp = score_words(perfect, rec, index, rows=word_truth(index, timeline), points=points)
    assert r_exact.recited_s == r_interp.recited_s
    assert r_exact.word_near == 1.0
    assert r_interp.word_near < r_exact.word_near, "letter counts miss these (made-up, even) timings"
