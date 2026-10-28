"""The Quran as a single normalized word stream, plus an inverted index over it.

Treating the whole text as one stream (~78k words) is what lets a query that
spans the end of one ayah and the start of the next match naturally: there is no
ayah boundary in the stream, only a `word_verse` lookup that says which ayah each
word belongs to.
"""

from __future__ import annotations

import math
from collections import defaultdict
from collections.abc import Callable

from rafiq.normalize import tokenize
from rafiq.quran import Quran


class QuranIndex:
    """Normalized word stream with postings and IDF weights. Immutable after build."""

    def __init__(self, quran: Quran, tokenizer: Callable[[str], list[str]] = tokenize) -> None:
        self.quran = quran
        self.tokenizer = tokenizer

        words: list[str] = []
        word_verse: list[int] = []
        verse_start = [0] * (len(quran) + 2)  # indexed by verse id; [len+1] is a sentinel
        for verse in quran:
            verse_start[verse.id] = len(words)
            tokens = tokenizer(verse.text)
            words.extend(tokens)
            word_verse.extend([verse.id] * len(tokens))
        verse_start[len(quran) + 1] = len(words)

        self.words = words
        self.word_verse = word_verse
        self._verse_start = verse_start

        postings: dict[str, list[int]] = defaultdict(list)
        for pos, word in enumerate(words):
            postings[word].append(pos)
        self.postings: dict[str, list[int]] = dict(postings)
        self.vocab: list[str] = sorted(self.postings)

        n_verses = len(quran)
        verse_freq = {w: len({word_verse[p] for p in ps}) for w, ps in self.postings.items()}
        self.idf: dict[str, float] = {w: math.log(1 + n_verses / df) for w, df in verse_freq.items()}

    def __len__(self) -> int:
        return len(self.words)

    def verse_span(self, verse_id: int) -> tuple[int, int]:
        """Stream range `[start, end)` covered by one verse."""
        return self._verse_start[verse_id], self._verse_start[verse_id + 1]

    def verse_at(self, pos: int) -> int:
        """Verse id of the word at stream position `pos` (clamped to the stream)."""
        return self.word_verse[min(max(pos, 0), len(self.words) - 1)]

    def text(self, start: int, end: int) -> str:
        return " ".join(self.words[max(start, 0) : end])


_cache: dict[int, QuranIndex] = {}


def get_index(quran: Quran | None = None) -> QuranIndex:
    """Shared index for a Quran (default: the bundled dataset). Building takes ~0.3 s."""
    from rafiq.quran import get_quran

    quran = quran or get_quran()
    key = id(quran)
    if key not in _cache:
        _cache[key] = QuranIndex(quran)
    return _cache[key]
