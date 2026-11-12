"""Exact word timings for evaluation, from quran-align (CC BY 4.0, Collin Fair).

quran-align (https://github.com/cpfair/quran-align, release 2016-11-24) gives,
for every ayah of 12 EveryAyah recitations, the milliseconds where each word
starts and ends inside that ayah's audio file. Its words are Tanzil's Uthmani
text split on spaces, without the pause marks (ۖ ۗ ۚ ...) and without the
basmala: checked against the data, this numbering gives the highest word index
of 99.8 to 99.9% of ayahs. That is exactly `Verse.text_uthmani` without its
pause marks. Rafiq's word stream is Simple Clean, normalized, and splits a few
words differently (the vocative: Uthmani "يٰٓأَيُّهَا" is our "يا ايها"), so the
two are mapped word by word (`map_words`).

The data is evaluation-only and not in git (`eval/fetch_quran_align.py`).
"""

from __future__ import annotations

import json
import re
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from rapidfuzz.distance import Levenshtein

from rafiq.matching.index import QuranIndex
from rafiq.normalize import normalize

# A token of only pause marks and other small signs: not a word for quran-align.
_MARK_ONLY = re.compile(r"^[ؐ-ؚۖ-ۭ࣓-ࣿ]+$")

# Word groupings tried when mapping (Uthmani words, our words), cheapest first.
_MOVES = ((1, 1), (1, 2), (2, 1), (1, 3), (3, 1), (2, 2))
_MOVE_COST = {(1, 1): 0.0, (1, 2): 0.05, (2, 1): 0.05, (1, 3): 0.1, (3, 1): 0.1, (2, 2): 0.15}


def load_segments(path: Path) -> dict[tuple[int, int], list[list[int]]]:
    """(surah, ayah) -> [[first word, word after the last, start ms, end ms], ...].

    The files are one JSON array, but one of them (Sudais) also carries the
    aligner's crash log on a line before it; only the array is read. An ayah
    the aligner could not time has no segments.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    data = json.loads(next(line for line in lines if line.startswith("[")))
    return {(e["surah"], e["ayah"]): e.get("segments") or [] for e in data}


def uthmani_words(text_uthmani: str) -> list[str]:
    """quran-align's words: the Uthmani text split on spaces, pause marks dropped."""
    return [t for t in text_uthmani.split(" ") if t and not _MARK_ONLY.match(t)]


@dataclass(frozen=True, slots=True)
class WordMap:
    groups: tuple[tuple[tuple[int, ...], tuple[int, ...]], ...]  # (Uthmani word indices, stream positions)
    worst: float  # lowest letter similarity of any group (0..1)

    @property
    def ok(self) -> bool:
        return self.worst >= MIN_SIMILARITY


MIN_SIMILARITY = 0.5  # below this, a group's letters are too unlike to trust the mapping


def map_verse(uthmani: Sequence[str], ours: Sequence[str], first_pos: int) -> WordMap:
    """Monotone alignment of one ayah's Uthmani words to our words, by letters."""
    u = [normalize(w).replace(" ", "") for w in uthmani]
    n, m = len(u), len(ours)
    inf = float("inf")
    cost = [[inf] * (m + 1) for _ in range(n + 1)]
    back: list[list[tuple[int, int] | None]] = [[None] * (m + 1) for _ in range(n + 1)]
    cost[0][0] = 0.0
    for i in range(n + 1):
        for j in range(m + 1):
            if cost[i][j] == inf:
                continue
            for a, b in _MOVES:
                if i + a > n or j + b > m:
                    continue
                sim = Levenshtein.normalized_similarity("".join(u[i : i + a]), "".join(ours[j : j + b]))
                c = cost[i][j] + (1.0 - sim) + _MOVE_COST[(a, b)]
                if c < cost[i + a][j + b]:
                    cost[i + a][j + b] = c
                    back[i + a][j + b] = (a, b)
    if cost[n][m] == inf:
        return WordMap((), 0.0)
    groups, worst = [], 1.0
    i, j = n, m
    while i or j:
        a, b = back[i][j]  # type: ignore[misc]
        i, j = i - a, j - b
        sim = Levenshtein.normalized_similarity("".join(u[i : i + a]), "".join(ours[j : j + b]))
        worst = min(worst, sim)
        groups.append((tuple(range(i, i + a)), tuple(first_pos + k for k in range(j, j + b))))
    return WordMap(tuple(reversed(groups)), worst)


def map_words(index: QuranIndex) -> dict[int, WordMap]:
    """Every verse id -> how its quran-align words map onto our word stream."""
    out = {}
    for v in index.quran:
        lo, hi = index.verse_span(v.id)
        out[v.id] = map_verse(uthmani_words(v.text_uthmani), index.words[lo:hi], lo)
    return out


def word_times(segments: list[list[int]], wmap: WordMap, index: QuranIndex) -> list[tuple[float, float, int]]:
    """(start s, end s, stream position) inside the ayah's audio file, for words with a timing.

    A segment over several Uthmani words, or one Uthmani word over several of
    ours, is shared out by letter count; several over one of ours are joined.
    Words the aligner left out have no timing and are not returned.
    """
    if not wmap.ok:
        return []
    u_times: dict[int, tuple[float, float]] = {}
    # A segment's time is shared out by each Uthmani word's letters, counted
    # as its share of the stream words it maps to.
    for first, after, start, end in segments:
        span = list(range(first, after))
        if not span:
            continue
        weights = [_u_weight(k, wmap, index) for k in span]
        total = sum(weights)
        acc = 0.0
        for k, w in zip(span, weights, strict=True):
            a = start + (end - start) * acc / total
            acc += w
            u_times[k] = (a / 1000, (start + (end - start) * acc / total) / 1000)
    out = []
    for us, ps in wmap.groups:
        if not all(k in u_times for k in us):
            continue
        a, b = u_times[us[0]][0], u_times[us[-1]][1]
        weights = [len(index.words[p]) for p in ps]
        total, acc = sum(weights), 0
        for p, w in zip(ps, weights, strict=True):
            s = a + (b - a) * acc / total
            acc += w
            out.append((s, a + (b - a) * acc / total, p))
    return out


def _u_weight(k: int, wmap: WordMap, index: QuranIndex) -> float:
    """Letters of Uthmani word `k`, as its share of the stream words it maps to."""
    for us, ps in wmap.groups:
        if k in us:
            return sum(len(index.words[p]) for p in ps) / len(us)
    return 1.0
