"""Product metrics over a tracked stream.

These are the metrics from the README, computed per step (one step = one ASR
chunk). Word error rate is deliberately absent: what users feel is whether the
screen shows the right ayah, how far off it is when it is not, and whether it
jumps around.

A chunk can straddle ayahs (the end of 78:8 and the start of al-Fatiha), so a
prediction is *acceptable* if it is within one ayah of any verse actually heard
in the chunk, and *exact* if it names the verse of the last word heard.

Noise chunks (no ground truth) are skipped for accuracy but still count for
stability, because a jump on a cough is exactly what we must not do.
"""

from __future__ import annotations

import statistics
from collections.abc import Sequence
from dataclasses import asdict, dataclass

from rafiq.simulate import Step
from rafiq.tracking import Tracker


@dataclass(frozen=True, slots=True)
class Report:
    steps: int
    accuracy: float  # displayed verse == verse of the last word heard
    acceptable: float  # within one ayah of something heard in the chunk
    coverage: float  # fraction of scored steps where something is displayed
    mean_abs_error: float  # ayahs to the nearest heard verse, over displayed steps
    wrong_jumps: int  # display changed to a verse that is not acceptable
    mean_recovery: float  # steps from going wrong to being acceptable again
    unrecovered: bool  # stream ended while wrong
    # Detection: the app starts knowing nothing and must find surah + ayah itself.
    time_to_lock: int | None  # chunks until the display is first right (None: never)
    first_shown_wrong: bool  # the first position ever displayed was wrong

    def to_dict(self) -> dict:
        return asdict(self)


def position_error(p: int, step: Step) -> int:
    """Distance in ayahs from `p` to the nearest verse heard in `step`."""
    heard = step.spoken or (step.truth_verse,)
    return min(abs(p - v) for v in heard)


def score(predicted: Sequence[int | None], steps: Sequence[Step]) -> Report:
    """Compare displayed verse ids with ground truth, step by step."""
    assert len(predicted) == len(steps)

    exact = acceptable = shown = 0
    errors: list[int] = []
    wrong_jumps = 0
    recoveries: list[int] = []
    wrong_since: int | None = None
    last_truth: Step | None = None
    prev: int | None = None
    lock: int | None = None
    first_shown_wrong: bool | None = None

    for i, (p, step) in enumerate(zip(predicted, steps, strict=True)):
        ref = step if step.truth_verse is not None else last_truth
        if step.truth_verse is not None:
            last_truth = step
        ok = p is not None and ref is not None and position_error(p, ref) <= 1

        if p is not None and p != prev and ref is not None and not ok:
            wrong_jumps += 1
        if p is not None:
            prev = p
            if first_shown_wrong is None:
                first_shown_wrong = not ok
        if ok and lock is None:
            lock = i + 1

        if step.truth_verse is None:
            continue
        exact += p == step.truth_verse
        acceptable += ok
        if p is not None:
            shown += 1
            errors.append(position_error(p, step))
        if not ok and wrong_since is None:
            wrong_since = i
        elif ok and wrong_since is not None:
            recoveries.append(i - wrong_since)
            wrong_since = None

    n = max(sum(s.truth_verse is not None for s in steps), 1)
    return Report(
        steps=len(steps),
        accuracy=exact / n,
        acceptable=acceptable / n,
        coverage=shown / n,
        mean_abs_error=statistics.fmean(errors) if errors else 0.0,
        wrong_jumps=wrong_jumps,
        mean_recovery=statistics.fmean(recoveries) if recoveries else 0.0,
        unrecovered=wrong_since is not None,
        time_to_lock=lock,
        first_shown_wrong=bool(first_shown_wrong),
    )


def run(tracker: Tracker, steps: Sequence[Step]) -> tuple[list[int | None], Report]:
    """Feed `steps` through a fresh tracker; returns displayed verses and the report."""
    tracker.reset()
    predicted = [tracker.update(s.text).verse_id for s in steps]
    return predicted, score(predicted, steps)
