"""Stateful position tracking: "given everything heard so far, where am I?"

The matcher answers "where could this chunk be?" — often ambiguously (the
refrain of Ar-Rahman occurs 31 times). The tracker resolves that with context,
using a small beam search over hypotheses, HMM-style:

    score(new) = max over previous hypotheses h of
                   decay * score(h) + transition(h -> candidate)
                 + emission(candidate)

* **emission** is the matcher's alignment score for the chunk.
* **transition** encodes how imams actually move: onward is free, a short step
  back (repeating an ayah) is cheap, anything far is expensive. It is a
  pluggable object so it can be tuned or learned without touching the search.
* **excursions** are regions the reciter visits and then *returns from* —
  al-Fatiha at the start of every rak'ah. Entering one is cheap, and leaving it
  is measured from where the reciter was before, not from the end of al-Fatiha.

On top of the search sits a display policy: a far jump must win `confirm`
times in a row before the screen moves. Showing a slightly stale ayah is far
better for the user than flickering across the mushaf.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field, replace
from typing import Protocol

from rafiq.matching import Match, Matcher

# Status values exposed to clients.
IDLE, TRACKING, UNCERTAIN, LOST = "idle", "tracking", "uncertain", "lost"


@dataclass(frozen=True, slots=True)
class TrackerConfig:
    beam: int = 8  # hypotheses kept between steps
    candidates: int = 8  # global matches requested per chunk
    local_hyps: int = 3  # top hypotheses that also get a local "expected next" check
    local_ahead: int = 40  # words beyond a hypothesis searched by that local check
    min_emission: float = 0.45  # a chunk whose best match scores lower is treated as noise
    decay: float = 0.6  # weight of history vs. the newest chunk
    miss_cost: float = 0.5  # penalty for a hypothesis that this chunk did not support
    confirm: int = 2  # consecutive wins a far jump needs before it is displayed
    cold_start_confidence: float = 0.6  # confidence needed to show the very first position
    full_evidence_words: int = 3  # chunks shorter than this count as proportionally weaker evidence
    unknown_exit_cost: float = 0.3  # leaving al-Fatiha when we never saw where the reciter was before
    hint_bonus: float = 0.3  # emission bonus inside the user's hint while searching (soft, never a filter)
    lost_after: int = 4  # consecutive noise chunks before reporting "lost"
    excursions: tuple[tuple[int, int], ...] = ((1, 7),)  # verse-id ranges: al-Fatiha


class TransitionModel(Protocol):
    def __call__(self, prev_end: int, next_start: int) -> float:
        """Log-score (<= 0) of moving from stream position `prev_end` to `next_start`."""
        ...


@dataclass(frozen=True, slots=True)
class DefaultTransition:
    """Piecewise prior over jumps, in words. See module docstring."""

    slack: int = 3  # |jump| this small is just chunking jitter
    forward_cost: float = 0.01  # per word skipped beyond the slack
    near: int = 40  # forward skips up to this many words are still "onward"
    back: int = 80  # backward jumps up to this many words count as a repetition
    repeat_cost: float = 0.4
    far_cost: float = 1.2

    def __call__(self, prev_end: int, next_start: int) -> float:
        jump = next_start - prev_end
        if -self.slack <= jump <= self.slack:
            return 0.0
        if self.slack < jump <= self.near:
            return -self.forward_cost * (jump - self.slack)
        if -self.back <= jump < -self.slack:
            return -self.repeat_cost
        return -self.far_cost


@dataclass(frozen=True, slots=True)
class Hypothesis:
    end: int  # stream position just after the last matched word
    score: float
    emission: float
    anchor: int | None = None  # where to return to after an excursion


@dataclass(frozen=True, slots=True)
class TrackState:
    verse_id: int | None  # displayed verse
    word: int | None  # displayed stream position (last recited word)
    status: str
    confidence: float
    candidates: list[Match] = field(default_factory=list)  # this chunk's matches, for debugging/UI
    pending_verse: int | None = None  # a far jump awaiting confirmation


class Tracker:
    def __init__(
        self,
        matcher: Matcher,
        config: TrackerConfig = TrackerConfig(),
        transition: TransitionModel | None = None,
    ) -> None:
        self._hint: tuple[int, int] | None = None  # stream range [lo, hi); survives reset()
        self.matcher = matcher
        self.index = matcher.index
        self.config = config
        self.transition = transition or DefaultTransition()
        self._excursion_spans = [
            (self.index.verse_span(a)[0], self.index.verse_span(b)[1]) for a, b in config.excursions
        ]
        self.reset()

    # -- public API ------------------------------------------------------

    def reset(self) -> None:
        self._hyps: list[Hypothesis] = []
        self._shown: int | None = None  # displayed stream position (end, exclusive)
        self._shown_anchor: int | None = None  # displayed position before entering an excursion
        self._pending: int | None = None
        self._pending_count = 0
        self._misses = 0
        self._state = TrackState(None, None, IDLE, 0.0)

    def hint(self, first_verse: int | None, last_verse: int | None = None) -> None:
        """Optional user hint: "tonight the imam is in this surah / juz".

        Detection is automatic without it. The hint only helps while the
        tracker is *searching* (before the first lock, or after getting lost):
        it adds a search restricted to the range and a small bonus for
        candidates inside it. Once locked, it has no effect, so a wrong hint
        can delay detection slightly but can never trap the tracker.
        Pass `None` to clear. It survives `reset()`: it describes the session.
        """
        if first_verse is None:
            self._hint = None
            return
        last_verse = last_verse or first_verse
        self._hint = (self.index.verse_span(first_verse)[0], self.index.verse_span(last_verse)[1])

    @property
    def searching(self) -> bool:
        """True until the first position is displayed, and again once lost."""
        return self._shown is None or self._misses >= self.config.lost_after

    @property
    def state(self) -> TrackState:
        return self._state

    def update(self, text: str) -> TrackState:
        """Feed one ASR chunk; returns what the UI should show now."""
        cfg = self.config
        tokens = self.index.tokenizer(text)
        hint = self._hint if self.searching else None
        candidates = self._candidates(tokens, hint)
        # A one-word chunk matches perfectly in hundreds of places; it is weak
        # evidence however well it aligns, so short chunks are discounted.
        evidence = min(1.0, len(tokens) / cfg.full_evidence_words)
        best_emission = evidence * max((c.score for c in candidates), default=0.0)

        if not tokens or best_emission < cfg.min_emission:
            self._misses += 1
            if self._shown is None:
                status = IDLE
            elif self._misses >= cfg.lost_after:
                status = LOST
            else:
                status = UNCERTAIN
            self._state = replace(self._state, status=status, candidates=candidates, confidence=0.0)
            return self._state

        self._misses = 0
        self._hyps = self._advance(candidates, evidence, hint)
        self._state = self._display(candidates)
        return self._state

    # -- search ----------------------------------------------------------

    def _candidates(self, tokens: list[str], hint: tuple[int, int] | None) -> list[Match]:
        if not tokens:
            return []
        cfg = self.config
        found = self.matcher.match_tokens(tokens, k=cfg.candidates)
        if hint:
            found += self.matcher.match_tokens(tokens, k=cfg.candidates, lo=hint[0], hi=hint[1])
        # Always check "right where I expect", so a poor global ranking can
        # never make the tracker lose a hypothesis that is still correct.
        for h in self._hyps[: cfg.local_hyps]:
            for origin in {h.end, h.anchor} - {None}:
                local = self.matcher.score_window(tokens, origin, origin + cfg.local_ahead)
                if local.score > 0:
                    found.append(local)
        unique: dict[tuple[int, int], Match] = {}
        for m in found:
            if (m.start, m.end) not in unique or m.score > unique[(m.start, m.end)].score:
                unique[(m.start, m.end)] = m
        return sorted(unique.values(), key=lambda m: m.score, reverse=True)

    def _in_excursion(self, pos: int) -> bool:
        return any(lo <= pos < hi for lo, hi in self._excursion_spans)

    def _transition(self, h: Hypothesis, c: Match) -> tuple[float, int | None]:
        """Score of h -> c, and the anchor the new hypothesis inherits."""
        if self._in_excursion(c.start):
            # Entering (or continuing in) al-Fatiha: cheap from anywhere; remember the way back.
            anchor = h.anchor if self._in_excursion(h.end - 1) else h.end
            inside = self.transition(h.end, c.start) if self._in_excursion(h.end - 1) else -0.1
            return max(inside, -0.1), anchor
        # Leaving an excursion is measured from where the reciter was before it:
        # after al-Fatiha the imam resumes his place, he does not start al-Baqarah.
        if self._in_excursion(h.end - 1) and h.anchor is None:
            # We joined mid-Fatiha and never saw where he was: every exit is
            # equally plausible, al-Baqarah gets no head start for adjacency.
            return -self.config.unknown_exit_cost, None
        origin = h.anchor if h.anchor is not None else h.end
        return self.transition(origin, c.start), None

    def _advance(
        self, candidates: list[Match], evidence: float, hint: tuple[int, int] | None
    ) -> list[Hypothesis]:
        cfg = self.config
        prior_hyps = self._hyps
        new: list[Hypothesis] = []
        for c in candidates:
            emission = evidence * c.score
            if emission < cfg.min_emission * 0.5:
                continue
            if hint and hint[0] <= c.start < hint[1]:
                emission += cfg.hint_bonus
            if prior_hyps:
                best_prev, anchor = -math.inf, None
                for h in prior_hyps:
                    t, a = self._transition(h, c)
                    s = cfg.decay * h.score + t
                    if s > best_prev:
                        best_prev, anchor = s, a
            else:
                best_prev = 0.0
                anchor = None
            new.append(Hypothesis(end=c.end, score=best_prev + emission, emission=emission, anchor=anchor))
        # Every hypothesis may also survive a chunk that does not support it.
        # Without this, one noisy chunk that happens to match far away would
        # wipe out the correct hypothesis and force the tracker to follow.
        for h in prior_hyps:
            new.append(replace(h, score=cfg.decay * h.score - cfg.miss_cost, emission=0.0))

        new.sort(key=lambda h: h.score, reverse=True)
        kept: list[Hypothesis] = []
        for h in new:
            if all(abs(h.end - k.end) > 2 for k in kept):
                kept.append(h)
                if len(kept) >= cfg.beam:
                    break
        return kept

    # -- display policy --------------------------------------------------

    def _is_near(self, a: int, b: int) -> bool:
        t = self.transition(a, b)
        return t > -getattr(self.transition, "far_cost", 1.0)

    def _display(self, candidates: list[Match]) -> TrackState:
        cfg = self.config
        best = self._hyps[0]
        rival = next((h for h in self._hyps[1:] if not self._is_near(best.end, h.end)
                      and not self._is_near(h.end, best.end)), None)  # fmt: skip
        margin = best.score - rival.score if rival else best.score
        confidence = best.emission * (1.0 - math.exp(-2.0 * max(margin, 0.0)))

        if self._shown is None:
            # Cold start: show nothing rather than a guess. A short first chunk
            # ("الحمد لله رب العالمين") is ambiguous, so it needs either high
            # confidence or the next chunk to agree.
            accept = confidence >= cfg.cold_start_confidence
        else:
            accept = (
                self._is_near(self._shown, best.end)
                or self._in_excursion(best.end - 1)
                or (self._shown_anchor is not None and self._is_near(self._shown_anchor, best.end))
            )
        if not accept:
            if self._pending is not None and self._is_near(self._pending, best.end):
                self._pending_count += 1
            else:
                self._pending_count = 1
            self._pending = best.end
            accept = self._pending_count >= cfg.confirm

        if accept:
            if self._in_excursion(best.end - 1):
                if not self._in_excursion(self._shown - 1 if self._shown else -1):
                    self._shown_anchor = self._shown
            else:
                self._shown_anchor = None
            self._shown = best.end
            self._pending, self._pending_count = None, 0

        pending_verse = self.index.verse_at(self._pending - 1) if self._pending is not None else None
        if self._shown is None:
            return TrackState(None, None, UNCERTAIN, round(confidence, 3), candidates, pending_verse)
        word = self._shown - 1
        status = TRACKING if confidence >= 0.5 and self._pending is None else UNCERTAIN
        return TrackState(
            verse_id=self.index.verse_at(word),
            word=word,
            status=status,
            confidence=round(confidence, 3),
            candidates=candidates,
            pending_verse=pending_verse,
        )
