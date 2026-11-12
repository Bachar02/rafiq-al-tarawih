"""Display policies over replayed results (rafiq.word_display): evaluation only."""

from __future__ import annotations

import pytest

from rafiq.matching import get_index
from rafiq.word_display import CONFIRMED, HIDDEN, PREDICTED, DisplayConfig, grid, render, score_display
from rafiq.word_eval import Shown, score_words, truth_points, word_truth


@pytest.fixture(scope="module")
def index():
    return get_index()


def breaths(index, verse, n=4, per=0.85):
    """Finals of steady breaths through `verse`, one word each (3.5-6 letters a second), 0.3 s late."""
    lo, _ = index.verse_span(verse)
    out, t = [], 0.0
    for k in range(n):
        out.append(Shown(at=t + per + 0.3, word=lo + k, verse=verse, end=t + per, start=t, final=True))
        t += per + 0.2
    return out


def test_nothing_is_shown_before_a_result_arrives(index):
    lo, _ = index.verse_span(2050)
    shown = [Shown(at=5.0, word=lo, verse=2050, end=4.6, start=4.0)]
    frames = render(shown, [1.0, 4.9, 5.0, 6.0], index, DisplayConfig())
    assert frames == [(None, HIDDEN), (None, HIDDEN), (lo, CONFIRMED), (lo, CONFIRMED)]


def test_a_stale_word_is_hidden(index):
    lo, _ = index.verse_span(2050)
    shown = [Shown(at=1.3, word=lo, verse=2050, end=1.0, start=0.0)]
    frames = render(shown, [1.5, 1.9, 2.1, 5.0], index, DisplayConfig(stale_after=1.0))
    assert [k for _, k in frames] == [CONFIRMED, CONFIRMED, HIDDEN, HIDDEN]


def test_prediction_waits_for_evidence_and_respects_its_limits(index):
    verse = 2050
    lo, hi = index.verse_span(verse)
    finals = breaths(index, verse, n=4)
    preview = Shown(at=5.2, word=lo + 4, verse=verse, end=5.0, start=4.8)  # a new breath is under way
    cfg = DisplayConfig(predict=True, max_ahead=1, min_samples=3, horizon=2.0)
    times = [5.3 + 0.1 * k for k in range(20)]
    frames = render([*finals, preview], times, index, cfg)
    kinds = {k for _, k in frames}
    assert PREDICTED in kinds, "three steady breaths are enough evidence"
    assert all(w <= lo + 5 for w, _ in frames if w is not None), "never more than one word ahead"
    assert all(k == HIDDEN or w is not None for w, k in frames)
    # Too little evidence: nothing predicted.
    few = render([*finals[:2], preview], times, index, cfg)
    assert PREDICTED not in {k for _, k in few}
    # After a final the imam has paused: no prediction unless asked to model the pause.
    after_final = render(finals, [finals[-1].at + 0.1 * k for k in range(15)], index, cfg)
    assert PREDICTED not in {k for _, k in after_final}
    # Never into the next ayah.
    last = Shown(at=5.2, word=hi - 1, verse=verse, end=5.0, start=4.8)
    edge = render([*finals, last], times, index, replace_cfg(cfg, max_ahead=3))
    assert all(w is None or w < hi for w, _ in edge)


def replace_cfg(cfg, **kw):
    from dataclasses import replace

    return replace(cfg, **kw)


def test_going_back_stops_prediction_for_a_while(index):
    verse = 2050
    lo, _ = index.verse_span(verse)
    finals = breaths(index, verse, n=4)
    back = Shown(at=5.2, word=lo, verse=verse, end=5.0, start=4.8)  # he went back to the start
    cfg = DisplayConfig(predict=True, min_samples=3, horizon=2.0, cooldown=2)
    frames = render([*finals, back], [5.3 + 0.1 * k for k in range(15)], index, cfg)
    assert PREDICTED not in {k for _, k in frames}


def test_baseline_scores_as_the_phase_three_scorer(index):
    timeline = [[0.0, 12.0, 2050]]
    rec = {"join": 0.0, "seconds": 12.0, "timeline": timeline, "events": []}
    rows = word_truth(index, timeline)
    lo, hi = index.verse_span(2050)
    shown = [Shown(at=a + 0.4, word=p, verse=2050, end=a) for a, _, p in rows[0].words]
    pts = truth_points(rows, rec)
    points = grid(rows, rec, pts)
    frames = render(shown, [t for t, _, _ in points], index, DisplayConfig())
    d = score_display(frames, points, rows, rec, index, 0.0)
    old = score_words(shown, rec, index, rows=rows, points=pts)
    assert d.confirmed + d.predicted + d.hidden == pytest.approx(1.0)
    assert d.confirmed == pytest.approx(old.coverage)
    assert d.useful == pytest.approx(old.useful)
    assert d.precision == pytest.approx(old.word_near)
    assert d.wrong_shown == pytest.approx(old.word_wrong)
