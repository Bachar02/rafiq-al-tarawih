"""Word-level local alignment (Smith-Waterman) with fuzzy word similarity.

Why word-level rather than character-level fuzzy matching: ASR errors are
mostly *per word* (a misheard word, a dropped word, a spurious word), and the
output we need is a span of words in the stream. Aligning words gives both the
right error model and the span for free.
"""

from __future__ import annotations

from dataclasses import dataclass

from rapidfuzz.distance import Levenshtein


@dataclass(frozen=True, slots=True)
class AlignConfig:
    gap: float = 0.5  # cost of skipping a word on either side
    min_word_sim: float = 0.5  # below this similarity two words count as a full mismatch


@dataclass(frozen=True, slots=True)
class Alignment:
    score: float  # raw alignment score; an exact match of n words scores n
    start: int  # window index of the first aligned word (inclusive)
    end: int  # window index after the last aligned word (exclusive)
    query_start: int
    query_end: int


def word_similarity(a: str, b: str, cfg: AlignConfig) -> float:
    """Substitution score in [-1, 1]: +1 identical, -1 unrelated."""
    if a == b:
        return 1.0
    sim = Levenshtein.normalized_similarity(a, b)
    if sim < cfg.min_word_sim:
        return -1.0
    return 2.0 * sim - 1.0


def align(query: list[str], window: list[str], cfg: AlignConfig = AlignConfig()) -> Alignment:
    """Best local alignment of `query` inside `window`."""
    n, m = len(query), len(window)
    if n == 0 or m == 0:
        return Alignment(0.0, 0, 0, 0, 0)

    sim_cache: dict[tuple[str, str], float] = {}
    gap = cfg.gap
    # Rolling rows. Each cell carries (score, window_start, query_start) so the
    # span is known without a traceback matrix.
    prev = [(0.0, j, 0) for j in range(m + 1)]
    best = Alignment(0.0, 0, 0, 0, 0)
    for i in range(1, n + 1):
        qw = query[i - 1]
        cur = [(0.0, 0, i)]
        for j in range(1, m + 1):
            ww = window[j - 1]
            key = (qw, ww)
            s = sim_cache.get(key)
            if s is None:
                s = sim_cache[key] = word_similarity(qw, ww, cfg)

            # A zero cell stores its own coordinates as the span start, so
            # extending from it starts a fresh alignment at this word.
            d_score, d_ws, d_qs = prev[j - 1]
            cell = (d_score + s, d_ws, d_qs)

            up_score, up_ws, up_qs = prev[j]  # skip a query word
            if up_score - gap > cell[0]:
                cell = (up_score - gap, up_ws, up_qs)
            left_score, left_ws, left_qs = cur[j - 1]  # skip a window word
            if left_score - gap > cell[0]:
                cell = (left_score - gap, left_ws, left_qs)

            if cell[0] <= 0.0:
                cell = (0.0, j, i)
            elif cell[0] > best.score:
                best = Alignment(cell[0], cell[1], j, cell[2], i)
            cur.append(cell)
        prev = cur
    return best
