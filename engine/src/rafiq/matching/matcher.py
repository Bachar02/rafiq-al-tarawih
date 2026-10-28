"""Text -> ranked candidate positions in the Quran.

Two stages, so each can be tuned or replaced independently:

1. **Retrieval** (cheap, recall-oriented). Every query word votes for the stream
   offset at which the query would have to start for that word to line up
   (`posting - query_index`). Votes are IDF-weighted, so rare words dominate.
   Out-of-vocabulary words (ASR misspellings) vote through their nearest
   vocabulary words at reduced weight.
2. **Rescoring** (precise). The best offsets are re-scored by word-level local
   alignment against the actual stream, which also yields the exact span.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

from rapidfuzz import fuzz, process

from rafiq.matching.align import AlignConfig, align
from rafiq.matching.index import QuranIndex


@dataclass(frozen=True, slots=True)
class MatchConfig:
    retrieve: int = 40  # offsets kept from voting for rescoring
    fuzzy_limit: int = 3  # vocabulary neighbours tried for an unknown word
    fuzzy_cutoff: float = 70.0  # rapidfuzz ratio needed for a neighbour to vote
    fuzzy_weight: float = 0.7  # neighbour votes count this much of an exact vote
    vote_spread: int = 2  # offsets within this many words pool their votes
    min_score: float = 0.25  # matches scoring below this are discarded
    align: AlignConfig = AlignConfig()


@dataclass(frozen=True, slots=True)
class Match:
    """A span of the stream that the query aligned to."""

    start: int  # stream word index, inclusive
    end: int  # stream word index, exclusive
    score: float  # alignment score / query length, in [0, 1]
    first_verse: int
    last_verse: int

    @property
    def verse_id(self) -> int:
        """Where the reciter is *now*: the verse containing the last matched word."""
        return self.last_verse


class Matcher:
    def __init__(self, index: QuranIndex, config: MatchConfig = MatchConfig()) -> None:
        self.index = index
        self.config = config
        self._neighbour_cache: dict[str, list[tuple[str, float]]] = {}

    # -- public API ------------------------------------------------------

    def match(self, text: str, k: int = 5, lo: int = 0, hi: int | None = None) -> list[Match]:
        """Top-`k` non-overlapping matches for `text`, best first.

        `lo`/`hi` restrict the search to a stream range — useful for seeding
        ("tonight is juz 5") or for local search around a known position.
        """
        tokens = self.index.tokenizer(text)
        return self.match_tokens(tokens, k=k, lo=lo, hi=hi)

    def match_tokens(self, tokens: list[str], k: int = 5, lo: int = 0, hi: int | None = None) -> list[Match]:
        if not tokens:
            return []
        hi = len(self.index) if hi is None else hi
        offsets = self._retrieve(tokens, lo, hi)
        matches = [self.score_window(tokens, off, off + len(tokens)) for off in offsets]
        return self._select(matches, k)

    def score_window(self, tokens: list[str], start: int, end: int) -> Match:
        """Align `tokens` against the stream around `[start, end)`.

        The window is padded on both sides so that a few inserted or deleted
        words cannot push the true span out of reach. The tracker uses this
        directly to check "is the reciter where I expect?" even when retrieval
        would not have surfaced that position.
        """
        n = len(tokens)
        pad = max(3, n // 2)
        w_lo = max(0, start - pad)
        w_hi = min(len(self.index), end + pad)
        window = self.index.words[w_lo:w_hi]
        a = align(tokens, window, self.config.align)
        s, e = w_lo + a.start, w_lo + max(a.end, a.start + 1)
        e = min(e, len(self.index))
        return Match(
            start=s,
            end=e,
            score=max(0.0, a.score / n),
            first_verse=self.index.verse_at(s),
            last_verse=self.index.verse_at(e - 1),
        )

    # -- internals -------------------------------------------------------

    def _neighbours(self, word: str) -> list[tuple[str, float]]:
        """Vocabulary words close to an out-of-vocabulary `word`, with weights."""
        cached = self._neighbour_cache.get(word)
        if cached is None:
            cfg = self.config
            found = process.extract(
                word,
                self.index.vocab,
                scorer=fuzz.ratio,
                limit=cfg.fuzzy_limit,
                score_cutoff=cfg.fuzzy_cutoff,
            )
            cached = [(w, cfg.fuzzy_weight * score / 100.0) for w, score, _ in found]
            self._neighbour_cache[word] = cached
        return cached

    def _retrieve(self, tokens: list[str], lo: int, hi: int) -> list[int]:
        index, cfg = self.index, self.config
        votes: dict[int, float] = defaultdict(float)
        for qi, token in enumerate(tokens):
            variants = [(token, 1.0)] if token in index.postings else self._neighbours(token)
            for word, weight in variants:
                w = weight * index.idf[word]
                for pos in index.postings[word]:
                    if lo <= pos < hi:
                        votes[pos - qi] += w
        if not votes:
            return []

        # Pool nearby offsets: an inserted or dropped word shifts the diagonal
        # by one, which would otherwise split the votes for the true position.
        spread = cfg.vote_spread
        pooled = {off: sum(votes.get(off + d, 0.0) for d in range(-spread, spread + 1)) for off in votes}
        ranked = sorted(pooled, key=pooled.__getitem__, reverse=True)

        chosen: list[int] = []
        for off in ranked:
            if all(abs(off - c) > spread for c in chosen):
                chosen.append(off)
                if len(chosen) >= cfg.retrieve:
                    break
        return chosen

    def _select(self, matches: list[Match], k: int) -> list[Match]:
        """Best-first, dropping matches that overlap a better one."""
        out: list[Match] = []
        for m in sorted(matches, key=lambda m: m.score, reverse=True):
            if m.score < self.config.min_score:
                break
            if any(m.start < o.end and o.start < m.end for o in out):
                continue
            out.append(m)
            if len(out) >= k:
                break
        return out
