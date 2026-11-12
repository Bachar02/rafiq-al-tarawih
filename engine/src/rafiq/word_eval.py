"""The word tracker on *real* speech-model output: replay recordings, score them.

A recording (`eval/audio_bench.py --record`, or the phone's
`integration_test/ondevice_test.dart`) holds what Whisper actually produced on
a stream with a known ayah timeline: every partial and final text, the audio
it covers, how long it took and when it was ready. Replaying it is exact for
everything that does not depend on the trackers, so the word tracker can be
measured on real recognition errors without running a model.

**Whisper is not a letter stream.** Each partial re-transcribes the whole
breath so far and may revise it ("ترره", then "بعيد", then "بعير ربي"), so
new letters cannot simply be appended. As the ayah tracker previews partials,
the word tracker is snapshotted at the start of each breath; every event
restores the snapshot and feeds that event's whole text, and a final commits
the result as the next snapshot.

**Anchoring** comes from the existing ayah tracker, replayed unchanged over the
same events (finals commit, partials preview): after a final, the word tracker
is anchored at the ayah tracker's word when it is idle or lost, or when the two
disagree by more than one ayah.

**Two kinds of truth, kept apart:**
* *exact*, ayah level: the timeline says which ayah is being recited when;
* *approximate*, word level: no word timings exist for these recordings, so
  each ayah's time is shared out among its words by letter count. Long madd
  and the silence inside a recording make this a word or two off at times.
"""

from __future__ import annotations

import copy
import statistics
from collections.abc import Sequence
from dataclasses import asdict, dataclass

from rafiq.matching import Matcher
from rafiq.matching.index import QuranIndex
from rafiq.tracking import TRACKING as AYAH_TRACKING
from rafiq.tracking import Tracker
from rafiq.words import IDLE, LOST, TRACKING, WordTracker, WordTrackerConfig


@dataclass(frozen=True, slots=True)
class Shown:
    """What the screen would show from `at` (seconds of listening) until the next one."""

    at: float
    word: int | None  # highlighted word (the word tracker is tracking), else None
    verse: int | None  # the ayah the ayah tracker shows
    end: float | None = None  # end of the audio the result covered (listening seconds)
    start: float | None = None  # start of that audio: the breath it belongs to
    final: bool = False  # the transcript at a pause (the imam has stopped), not a live preview


def _snapshot(tracker: WordTracker) -> WordTracker:
    """A copy that shares the (large, immutable) index and config."""
    return copy.deepcopy(tracker, {id(tracker.index): tracker.index, id(tracker.config): tracker.config})


def replay_words(
    recording: dict,
    matcher: Matcher,
    finals_only: bool = False,
    pause_after: float = 2.5,
    config: WordTrackerConfig = WordTrackerConfig(),
) -> list[Shown]:
    """Replay one recording through the ayah tracker and the word tracker."""
    index = matcher.index
    ayahs = Tracker(matcher)
    base = WordTracker(index, config)
    shown: list[Shown] = []
    segment: float | None = None  # start of the current breath
    last_end: float | None = None
    for e in recording["events"]:
        final = bool(e["final"])
        if finals_only and not final:
            continue
        if e["start"] != segment:
            if last_end is not None and e["start"] - last_end > pause_after:
                base.pause()
            segment = e["start"]
        state = ayahs.update(e["text"]) if final else ayahs.preview(e["text"])
        work = base if final else _snapshot(base)
        word_state = work.feed(e["text"])
        if final:
            last_end = e["end"]
            segment = None  # the next event starts a new breath
            if state.status == AYAH_TRACKING and state.word is not None:
                ws = base.state
                at = ws.word if ws.word is not None else None
                disagree = at is not None and abs(index.verse_at(at) - state.verse_id) > 1
                if ws.status in (IDLE, LOST) or disagree:
                    word_state = base.anchor(state.word)
        word = word_state.word if word_state.status == TRACKING else None
        shown.append(Shown(e["ready"], word, state.showing, e["end"], e["start"], final))
    return shown


@dataclass(frozen=True, slots=True)
class TruthRow:
    start: float  # stream seconds
    end: float
    verse: int
    words: tuple[tuple[float, float, int], ...]  # (start, end, stream position); empty for a basmala


def word_truth(index: QuranIndex, timeline: Sequence[Sequence]) -> list[TruthRow]:
    """The timeline, with each ayah's time shared out among its words by letter count.

    Verse id 1 followed by anything but 2 is a basmala before a surah, not
    al-Fatiha 1:1: its words are not scored.
    """
    rows = []
    for i, (start, end, verse) in enumerate(timeline):
        nxt = timeline[i + 1][2] if i + 1 < len(timeline) else None
        if verse == 1 and nxt != 2:
            rows.append(TruthRow(start, end, verse, ()))
            continue
        lo, hi = index.verse_span(verse)
        sizes = [len(index.words[p]) for p in range(lo, hi)]
        total, acc, words = sum(sizes), 0, []
        for p, n in zip(range(lo, hi), sizes, strict=True):
            a = start + (end - start) * acc / total
            acc += n
            words.append((a, start + (end - start) * acc / total, p))
        rows.append(TruthRow(start, end, verse, tuple(words)))
    return rows


def exact_truth(
    index: QuranIndex,
    timeline: Sequence[Sequence],
    segments: dict[tuple[int, int], list[list[int]]],
    maps: dict,
    exclude: frozenset[str] = frozenset(),
) -> list[TruthRow]:
    """The timeline with quran-align's word times (`rafiq.word_truth`), where they can be trusted.

    An ayah in `exclude` (it failed the audio check), one the aligner could not
    time, and a basmala row get no words, so they are not scored word by word.
    """
    from rafiq.word_truth import word_times

    quran = index.quran
    rows = []
    for i, (start, end, verse) in enumerate(timeline):
        nxt = timeline[i + 1][2] if i + 1 < len(timeline) else None
        v = quran.by_id(verse)
        if (verse == 1 and nxt != 2) or v.ref in exclude:
            rows.append(TruthRow(start, end, verse, ()))
            continue
        times = word_times(segments.get((v.surah, v.ayah), []), maps[verse], index)
        rows.append(TruthRow(start, end, verse, tuple((start + a, start + b, p) for a, b, p in times)))
    return rows


def truth_points(rows: Sequence[TruthRow], recording: dict, step: float = 0.1) -> frozenset[int]:
    """Grid steps (k: at k * step seconds of listening) where `rows` say which word is being recited."""
    join, out = recording["join"], set()
    for k in range(int(recording["seconds"] / step)):
        ts = k * step + join
        for r in rows:
            if r.start <= ts < r.end:
                if any(a <= ts < b for a, b, _ in r.words):
                    out.add(k)
                break
    return frozenset(out)


@dataclass(frozen=True, slots=True)
class RealWordReport:
    recited_s: float  # seconds of recitation scored (inside ayahs, after listening began)
    coverage: float  # share of it with a word highlighted
    first_s: float | None  # seconds of listening until a word of the right ayah is first highlighted
    # Exact (ayah timeline), over highlighted time:
    ayah_same: float  # the highlighted word is in the ayah being recited
    ayah_wrong: float  # ...in neither that ayah nor the one before it (lag explains the one before)
    ayah_wrong_per_hour: float  # separate stretches of such wrong highlights, per hour of recitation
    ayah_shown_same: float  # for comparison: the ayah tracker shows the ayah being recited (all scored time)
    # Approximate (interpolated word times), over highlighted time:
    word_near: float  # within one word
    word_wrong: float  # more than two words off
    useful: float  # share of all recited time with a highlight within one word (stale ones do not count)
    aligned: float  # per result with a highlight: within one word of the truth at the end of the audio
    # it covered. The tracker's own accuracy, without the model's lag.
    word_delay_median: float | None  # a word starts -> it (or a later one of its ayah) is highlighted
    word_delay_p90: float | None
    words_reached: float  # share of words, after the first highlight, highlighted before their ayah ends
    recovery_median: float | None  # a stretch without a right highlight -> right again
    recovery_p90: float | None
    # Speech model, over the events used:
    events: int
    asr_ms_median: float | None
    asr_ms_p90: float | None
    age_median: float | None  # end of the audio a result covers -> the result is ready (seconds)
    age_p90: float | None

    def to_dict(self) -> dict:
        return asdict(self)


def _pct(values: list[float], q: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s) - 1, max(0, int(round(q * (len(s) - 1)))))]


def score_words(
    shown: Sequence[Shown],
    recording: dict,
    index: QuranIndex,
    finals_only: bool = False,
    step: float = 0.1,
    rows: Sequence[TruthRow] | None = None,
    points: frozenset[int] | None = None,
) -> RealWordReport:
    """Score what the screen showed, on a `step`-second grid, against the timeline.

    `rows` is the word truth (default: interpolated by letter count). With
    `points`, only those grid steps are scored, so two kinds of truth can be
    compared at the very same moments.
    """
    join, seconds = recording["join"], recording["seconds"]
    rows = list(rows) if rows is not None else word_truth(index, recording["timeline"])

    def row_at(ts: float) -> int | None:
        for i, r in enumerate(rows):
            if r.start <= ts < r.end:
                return i
        return None

    # The grid: (listening time, row index, truth word or None), inside ayahs only.
    grid: list[tuple[float, int, int | None]] = []
    n = int(seconds / step)
    for k in range(n):
        if points is not None and k not in points:
            continue
        t = k * step
        i = row_at(t + join)
        if i is None:
            continue
        truth = next((p for a, b, p in rows[i].words if a <= t + join < b), None)
        grid.append((t, i, truth))

    j, cur = 0, Shown(-1.0, None, None)
    on: list[tuple[float, int, int | None, Shown]] = []
    for t, i, truth in grid:
        while j < len(shown) and shown[j].at <= t:
            cur = shown[j]
            j += 1
        on.append((t, i, truth, cur))

    scored = [x for x in on if rows[x[1]].words]  # not the basmala
    lit = [x for x in scored if x[3].word is not None]
    same = wrong_ayah = near = wrong_word = 0
    episodes, in_wrong = 0, False
    first = None
    for t, i, truth, s in scored:
        w = s.word
        if w is None:
            in_wrong = False
            continue
        v = index.verse_at(w)
        ok_ayah = v == rows[i].verse
        prev_ok = i > 0 and v == rows[i - 1].verse
        same += ok_ayah
        bad = not ok_ayah and not prev_ok
        wrong_ayah += bad
        if bad and not in_wrong:
            episodes += 1
        in_wrong = bad
        if ok_ayah and first is None:
            first = t
        if truth is not None:
            near += abs(w - truth) <= 1
            wrong_word += abs(w - truth) > 2
    shown_same = sum(1 for t, i, _, s in scored if s.verse == rows[i].verse)

    # Word delay and reach: each word starting after the first highlight.
    delays: list[float] = []
    reached = counted = 0
    by_row: dict[int, list[tuple[float, int]]] = {}
    for t, i, _, s in on:
        if s.word is not None and index.verse_at(s.word) == rows[i].verse:
            by_row.setdefault(i, []).append((t, s.word))
    if first is not None:
        for i, r in enumerate(rows):
            lit_here = by_row.get(i, [])
            for a, _, p in r.words:
                ta = a - join
                if ta < first:
                    continue
                counted += 1
                hit = next((t for t, w in lit_here if t >= ta and w >= p), None)
                if hit is not None:
                    reached += 1
                    delays.append(hit - ta)

    # Recovery: from losing a right highlight (none, or more than a word off) to having one again.
    recoveries: list[float] = []
    bad_since: float | None = None
    started = False
    for t, _, truth, s in scored:
        good = s.word is not None and truth is not None and abs(s.word - truth) <= 1
        if good:
            if bad_since is not None:
                recoveries.append(t - bad_since)
            bad_since, started = None, True
        elif started and bad_since is None and truth is not None:
            bad_since = t

    events = [e for e in recording["events"] if e["final"] or not finals_only]
    aligned = with_word = 0
    for s in shown:
        if s.word is None or s.end is None:
            continue
        if points is not None and int(s.end / step) not in points:
            continue
        i = row_at(s.end + join)
        if i is None or not rows[i].words:
            continue
        truth = next((p for a, b, p in rows[i].words if a <= s.end + join < b), None)
        if truth is not None:
            with_word += 1
            aligned += abs(s.word - truth) <= 1
    asr = [float(e["asr_ms"]) for e in events]
    age = [e["ready"] - e["end"] for e in events]
    recited = len(scored) * step
    hours = recited / 3600

    def frac(a: int, b: int) -> float:
        return a / b if b else 0.0

    return RealWordReport(
        recited_s=round(recited, 1),
        coverage=frac(len(lit), len(scored)),
        first_s=first,
        ayah_same=frac(same, len(lit)),
        ayah_wrong=frac(wrong_ayah, len(lit)),
        ayah_wrong_per_hour=episodes / hours if hours else 0.0,
        ayah_shown_same=frac(shown_same, len(scored)),
        word_near=frac(near, len(lit)),
        word_wrong=frac(wrong_word, len(lit)),
        useful=frac(near, len(scored)),
        aligned=frac(aligned, with_word),
        word_delay_median=statistics.median(delays) if delays else None,
        word_delay_p90=_pct(delays, 0.9),
        words_reached=frac(reached, counted),
        recovery_median=statistics.median(recoveries) if recoveries else None,
        recovery_p90=_pct(recoveries, 0.9),
        events=len(events),
        asr_ms_median=statistics.median(asr) if asr else None,
        asr_ms_p90=_pct(asr, 0.9),
        age_median=statistics.median(age) if age else None,
        age_p90=_pct(age, 0.9),
    )
