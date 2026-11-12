"""What a word highlight could show between speech-model results: evaluation only.

The word tracker is accurate, but Whisper's results arrive in steps (every
~0.5 s with live previews, only at pauses without) and describe audio that is
already 0.35 s old or more (PLAN.md §31). These display policies decide, at
every moment, what the screen would highlight from the results that have
*arrived by then*:

* **confirmed**: the word the latest result put the word tracker on;
* **predicted**: a later word, estimated from the imam's pace since then;
* **hidden**: nothing, because the evidence is too old or too weak.

Two experiments, alone or together:

1. **Stale-highlight suppression** (`stale_after`): hide a confirmed word once
   the audio behind it is older than this. A held madd keeps the imam on one
   word for seconds, so hiding early also hides right words.
2. **Predictive advancement** (`predict`): the pace in letters per second of
   speech is measured on each finished breath (the letters between the words
   of two finals, over the breath's audio). Between results the highlight walks
   on at that pace from where the imam was when the last result's audio
   ended, by at most `max_ahead` words, never into the next ayah, never after
   a pause unless `across_pause`, never before `min_samples` breaths agree on a
   plausible pace, and not for `cooldown` results after the imam went back
   (a repeat, a correction, al-Fatiha). Past `horizon` seconds of evidence it
   stops predicting.

Nothing here sees the truth: `render` hands each policy only the results whose
arrival time has passed. `score_display` then scores the frames per kind.
"""

from __future__ import annotations

import statistics
from collections.abc import Sequence
from dataclasses import asdict, dataclass

from rafiq.matching.index import QuranIndex
from rafiq.word_eval import Shown, TruthRow

CONFIRMED, PREDICTED, HIDDEN = "confirmed", "predicted", "hidden"


@dataclass(frozen=True, slots=True)
class DisplayConfig:
    stale_after: float | None = None  # hide a confirmed word once its audio is older than this (s)
    predict: bool = False
    max_ahead: int = 1  # words a prediction may run ahead of the confirmed word
    kappa: float = 0.5  # where in the confirmed word the imam was when its audio ended (0 start, 1 end)
    horizon: float = 1.5  # predict for at most this long after the confirmed word's audio (s)
    min_samples: int = 3  # breaths with a plausible pace before predicting at all
    alpha: float = 0.3  # weight of the newest breath in the pace
    cooldown: int = 2  # results without prediction after the imam went back
    across_pause: bool = False  # after a pause, predict from the usual pause length
    min_rate: float = 3.0  # letters per second of speech considered plausible
    max_rate: float = 25.0

    @property
    def name(self) -> str:
        parts = []
        if self.predict:
            parts.append(
                f"predict a{self.max_ahead} k{self.kappa:g} h{self.horizon:g} n{self.min_samples}"
                + (" +pause" if self.across_pause else "")
            )
        if self.stale_after is not None:
            parts.append(f"hide>{self.stale_after:g}s")
        return ", ".join(parts) or "baseline"


class DisplayPolicy:
    """Decides, from the results so far, what to highlight at a moment."""

    def __init__(self, index: QuranIndex, config: DisplayConfig) -> None:
        self.index = index
        self.config = config
        words = index.words
        self._cum = [0] * (len(words) + 1)  # letters before each stream position
        for p, w in enumerate(words):
            self._cum[p + 1] = self._cum[p] + len(w)
        self._last: Shown | None = None
        self._prev_final_word: int | None = None
        self._last_final_end: float | None = None
        self._breath: float | None = None
        self._rate: float | None = None
        self._samples = 0
        self._gap: float | None = None
        self._cooldown = 0

    def on_result(self, s: Shown) -> None:
        cfg = self.config
        last = self._last
        if s.start is not None and s.start != self._breath:
            # A new breath: how long the imam paused before it.
            if self._last_final_end is not None and 0.0 < s.start - self._last_final_end < 10.0:
                g = s.start - self._last_final_end
                self._gap = g if self._gap is None else self._gap + cfg.alpha * (g - self._gap)
            self._breath = s.start
        if last is not None and last.word is not None and s.word is not None and s.word < last.word:
            # He went back (a repeat, a correction, al-Fatiha): stop predicting a while.
            self._cooldown = cfg.cooldown
            self._prev_final_word = None
        elif self._cooldown:
            self._cooldown -= 1
        if s.final:
            if (
                s.word is not None
                and self._prev_final_word is not None
                and s.word > self._prev_final_word
                and s.start is not None
                and s.end is not None
                and s.end - s.start >= 0.8
            ):
                rate = (self._cum[s.word + 1] - self._cum[self._prev_final_word + 1]) / (s.end - s.start)
                if cfg.min_rate <= rate <= cfg.max_rate:
                    self._rate = rate if self._rate is None else self._rate + cfg.alpha * (rate - self._rate)
                    self._samples += 1
            self._prev_final_word = s.word
            self._last_final_end = s.end
        self._last = s

    def at(self, t: float) -> tuple[int | None, str]:
        cfg = self.config
        s = self._last
        if s is None or s.word is None or s.end is None:
            return None, HIDDEN
        age = t - s.end
        if (
            cfg.predict
            and self._rate is not None
            and self._samples >= cfg.min_samples
            and not self._cooldown
            and age <= cfg.horizon
        ):
            ref: float | None = s.end
            if s.final:
                ref = s.end + self._gap if (cfg.across_pause and self._gap is not None) else None
            if ref is not None:
                w = s.word
                here = self._cum[w] + cfg.kappa * len(self.index.words[w]) + self._rate * max(0.0, t - ref)
                _, verse_end = self.index.verse_span(self.index.verse_at(w))
                cap = min(w + cfg.max_ahead, verse_end - 1)
                target = w
                while target < cap and self._cum[target + 1] <= here:
                    target += 1
                return (target, PREDICTED) if target > w else (w, CONFIRMED)
        if cfg.stale_after is not None and age > cfg.stale_after:
            return None, HIDDEN
        return s.word, CONFIRMED


def render(
    shown: Sequence[Shown], times: Sequence[float], index: QuranIndex, config: DisplayConfig
) -> list[tuple[int | None, str]]:
    """The highlight at each of `times` (ascending), from the results arrived by then only."""
    policy = DisplayPolicy(index, config)
    out, j = [], 0
    for t in times:
        while j < len(shown) and shown[j].at <= t:
            policy.on_result(shown[j])
            j += 1
        out.append(policy.at(t))
    return out


@dataclass(frozen=True, slots=True)
class DisplayReport:
    scored_s: float
    # What the screen shows, as shares of recited time (they add up to 1):
    confirmed: float
    predicted: float
    hidden: float
    # Right and wrong, as shares of recited time:
    useful: float  # a word within one of the one being recited
    useful_confirmed: float
    useful_predicted: float
    wrong: float  # a word more than two off
    wrong_confirmed: float
    wrong_predicted: float
    wrong_ayah: float  # (exact) a word in neither the ayah being recited nor the one before
    # Of the time something is shown:
    precision: float  # within one word
    wrong_shown: float  # more than two words off
    # Episodes:
    wrong_per_hour: float  # separate stretches of a word more than two off
    wrong_ayah_per_hour: float
    backjumps_per_min: float  # the highlight moves back (a flicker after a wrong guess, or a repeat)
    hidden_per_min: float  # separate stretches without a highlight
    hidden_median_s: float | None
    # Latency (a word starts -> it or a later word of its ayah is shown):
    latency_median: float | None
    latency_p90: float | None
    latency_confirmed_median: float | None  # ...counting confirmed highlights only
    reached: float  # words shown before their ayah ends
    recovery_median: float | None  # a stretch without a right highlight -> right again
    recovery_p90: float | None

    def to_dict(self) -> dict:
        return asdict(self)


def _pct(values: list[float], q: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s) - 1, max(0, int(round(q * (len(s) - 1)))))]


def grid(
    rows: Sequence[TruthRow], recording: dict, points: frozenset[int], step: float = 0.1
) -> list[tuple[float, int, int | None]]:
    """(listening time, row, truth word) at each scored grid step, in order."""
    join, out = recording["join"], []
    for k in sorted(points):
        t = k * step
        ts = t + join
        for i, r in enumerate(rows):
            if r.start <= ts < r.end:
                truth = next((p for a, b, p in r.words if a <= ts < b), None)
                if r.words:
                    out.append((t, i, truth))
                break
    return out


def score_display(
    frames: Sequence[tuple[int | None, str]],
    points: Sequence[tuple[float, int, int | None]],
    rows: Sequence[TruthRow],
    recording: dict,
    index: QuranIndex,
    latency_from: float | None,
    step: float = 0.1,
) -> DisplayReport:
    """Score rendered `frames` at `points` (from `grid`) against the truth `rows`.

    `latency_from`: words starting before this (listening seconds) are not
    timed, so every policy is timed on the same words.
    """
    n = len(points)
    join = recording["join"]
    count = {CONFIRMED: 0, PREDICTED: 0, HIDDEN: 0}
    useful = {CONFIRMED: 0, PREDICTED: 0}
    wrong = {CONFIRMED: 0, PREDICTED: 0}
    wrong_ayah = 0
    wrong_eps = ayah_eps = backjumps = 0
    hidden_runs: list[float] = []
    prev_t = None
    prev_wrong = prev_ayah_wrong = False
    hidden_since: float | None = None
    last_shown: int | None = None
    recoveries: list[float] = []
    bad_since: float | None = None
    started = False
    by_row: dict[int, list[tuple[float, int, str]]] = {}
    for (t, i, truth), (w, kind) in zip(points, frames, strict=True):
        contiguous = prev_t is not None and t - prev_t <= 1.5 * step
        count[kind] += 1
        is_wrong = is_ayah_wrong = False
        if w is not None:
            v = index.verse_at(w)
            if v != rows[i].verse and not (i > 0 and v == rows[i - 1].verse):
                is_ayah_wrong = True
                wrong_ayah += 1
            if truth is not None:
                if abs(w - truth) <= 1:
                    useful[kind] += 1
                elif abs(w - truth) > 2:
                    wrong[kind] += 1
                    is_wrong = True
            if last_shown is not None and w < last_shown:
                backjumps += 1
            last_shown = w
            if v == rows[i].verse:
                by_row.setdefault(i, []).append((t, w, kind))
        if is_wrong and not (prev_wrong and contiguous):
            wrong_eps += 1
        if is_ayah_wrong and not (prev_ayah_wrong and contiguous):
            ayah_eps += 1
        prev_wrong, prev_ayah_wrong = is_wrong, is_ayah_wrong
        if kind == HIDDEN:
            if hidden_since is None or not contiguous:
                if hidden_since is not None and prev_t is not None:
                    hidden_runs.append(prev_t - hidden_since + step)
                hidden_since = t
        elif hidden_since is not None:
            hidden_runs.append(t - hidden_since)
            hidden_since = None
        good = w is not None and truth is not None and abs(w - truth) <= 1
        if good:
            if bad_since is not None:
                recoveries.append(t - bad_since)
            bad_since, started = None, True
        elif started and bad_since is None and truth is not None:
            bad_since = t
        prev_t = t
    if hidden_since is not None and prev_t is not None:
        hidden_runs.append(prev_t - hidden_since + step)

    latencies, confirmed_lat = [], []
    reached = counted = 0
    if latency_from is not None:
        for i, r in enumerate(rows):
            shown_here = by_row.get(i, [])
            for a, _, p in r.words:
                ta = a - join
                if ta < latency_from:
                    continue
                counted += 1
                hit = next((t for t, w, _ in shown_here if t >= ta and w >= p), None)
                if hit is not None:
                    reached += 1
                    latencies.append(hit - ta)
                hit_c = next((t for t, w, k in shown_here if t >= ta and w >= p and k == CONFIRMED), None)
                if hit_c is not None:
                    confirmed_lat.append(hit_c - ta)

    shown_n = n - count[HIDDEN]
    hours = n * step / 3600
    minutes = n * step / 60

    def frac(a: int, b: int) -> float:
        return a / b if b else 0.0

    return DisplayReport(
        scored_s=round(n * step, 1),
        confirmed=frac(count[CONFIRMED], n),
        predicted=frac(count[PREDICTED], n),
        hidden=frac(count[HIDDEN], n),
        useful=frac(useful[CONFIRMED] + useful[PREDICTED], n),
        useful_confirmed=frac(useful[CONFIRMED], n),
        useful_predicted=frac(useful[PREDICTED], n),
        wrong=frac(wrong[CONFIRMED] + wrong[PREDICTED], n),
        wrong_confirmed=frac(wrong[CONFIRMED], n),
        wrong_predicted=frac(wrong[PREDICTED], n),
        wrong_ayah=frac(wrong_ayah, n),
        precision=frac(useful[CONFIRMED] + useful[PREDICTED], shown_n),
        wrong_shown=frac(wrong[CONFIRMED] + wrong[PREDICTED], shown_n),
        wrong_per_hour=wrong_eps / hours if hours else 0.0,
        wrong_ayah_per_hour=ayah_eps / hours if hours else 0.0,
        backjumps_per_min=backjumps / minutes if minutes else 0.0,
        hidden_per_min=len(hidden_runs) / minutes if minutes else 0.0,
        hidden_median_s=statistics.median(hidden_runs) if hidden_runs else None,
        latency_median=statistics.median(latencies) if latencies else None,
        latency_p90=_pct(latencies, 0.9),
        latency_confirmed_median=statistics.median(confirmed_lat) if confirmed_lat else None,
        reached=frac(reached, counted),
        recovery_median=statistics.median(recoveries) if recoveries else None,
        recovery_p90=_pct(recoveries, 0.9),
    )
