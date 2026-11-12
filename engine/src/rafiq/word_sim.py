"""Synthetic letter streams, as a streaming CTC model would emit them.

The word tracker (`rafiq.words`) is built and measured before any such model
exists. This is its test bench, as `rafiq.simulate` was for the ayah tracker:
the imam recites a passage, letter by letter with timing, and what goes wrong
in a mosque is modelled at the letter level. Letters are misheard, dropped
(written-but-silent ones more often) or invented; a word comes out as noise;
the imam goes back a few words or repeats the ayah; "amin" and coughs; the
basmala aloud or not; al-Fatiha at the start of each rakʿah.

Every letter carries the truth (the word being recited), so `score` can say
how often the highlighted word is right, how late it is, and above all how
often a wrong word is highlighted.

`run` also plays the part of the ayah tracker: it anchors the word tracker
when recitation starts, after each jump it cannot follow by itself (into and
out of al-Fatiha), and when it reports itself lost, each time `anchor_delay`
seconds late and at the word heard two seconds before that, as a Whisper
result would.
"""

from __future__ import annotations

import random
import statistics
from dataclasses import dataclass

from rafiq.matching.index import QuranIndex
from rafiq.simulate import CONFUSABLE
from rafiq.words import LOST, TRACKING, WEAK, WordTracker

LETTERS = "ابتثجحخدذرزسشصضطظعغفقكلمنهوي"
FILLERS = ["امين", "اللهاكبر", "سمعاللهلمنحمده", "هه", "احم"]


@dataclass(frozen=True, slots=True)
class LetterNoise:
    sub: float = 0.06  # a letter heard as another (a similar one 70% of the time)
    drop: float = 0.05  # a letter not heard (written-but-silent ones three times as often)
    insert: float = 0.03  # a spurious letter after this one
    garble: float = 0.03  # a whole word comes out as noise
    repeat: float = 0.15  # per ayah: the imam goes back 2 to 6 words, then on
    restart: float = 0.03  # per ayah: the imam recites the whole ayah again
    filler: float = 0.03  # per ayah: a burst that is not Quran ("amin", a cough, takbir)
    basmala: float = 0.5  # the basmala before ayah 1 is recited aloud
    fatiha_every: int = 0  # al-Fatiha every N ayahs (a new rakʿah); 0: never

    @classmethod
    def preset(cls, name: str) -> LetterNoise:
        return {
            "clean": cls(sub=0.02, drop=0.02, insert=0.01, garble=0, repeat=0.05, restart=0, filler=0),
            "light": cls(),
            "heavy": cls(sub=0.12, drop=0.10, insert=0.06, garble=0.08, filler=0.06),
            "broken": cls(sub=0.25, drop=0.18, insert=0.10, garble=0.20, filler=0.10),
        }[name]


@dataclass(frozen=True, slots=True)
class Letter:
    ch: str
    time: float  # seconds from the start of the stream
    word: int | None  # stream position of the word being recited; None: not Quran text
    basmala: int | None = None  # reciting the basmala before this verse id


def simulate_letters(
    index: QuranIndex, first: int, last: int, noise: LetterNoise, seed: int = 0
) -> list[Letter]:
    """The imam recites verses `first..last` (global ids), as a CTC model hears it."""
    rng = random.Random(seed)
    speed = rng.uniform(0.75, 1.4)  # this reciter's tempo
    out: list[Letter] = []
    t = 0.0
    quran = index.quran
    basmala_words = index.words[slice(*index.verse_span(1))]

    def say(words: list[str], truth: list[int | None], basmala: int | None = None) -> None:
        nonlocal t
        for text, w in zip(words, truth, strict=True):
            if w is not None and rng.random() < noise.garble:
                text = "".join(rng.choice(LETTERS) for _ in range(max(1, len(text) + rng.randint(-1, 1))))
            for ch in text:
                t += rng.uniform(0.06, 0.11) * speed
                if ch in WEAK and rng.random() < 0.2:
                    t += rng.uniform(0.2, 0.8)  # madd: held, still one letter
                p_drop = noise.drop * (3 if ch in WEAK else 1)
                if rng.random() < p_drop:
                    continue
                if rng.random() < noise.sub:
                    ch = CONFUSABLE[ch] if ch in CONFUSABLE and rng.random() < 0.7 else rng.choice(LETTERS)
                out.append(Letter(ch, t, w, basmala))
                if rng.random() < noise.insert:
                    out.append(Letter(rng.choice(LETTERS), t + 0.03, w, basmala))
            if rng.random() < 0.08:
                t += rng.uniform(0.2, 0.6)  # a breath inside the ayah

    def ayah(verse: int) -> None:
        nonlocal t
        lo, hi = index.verse_span(verse)
        v = quran.by_id(verse)
        if v.ayah == 1 and quran.surah(v.surah).has_basmala and rng.random() < noise.basmala:
            say(list(basmala_words), [None] * len(basmala_words), basmala=verse)
            t += rng.uniform(0.3, 1.0)
        positions = list(range(lo, hi))
        say([index.words[p] for p in positions], list(positions))
        if len(positions) > 4 and rng.random() < noise.repeat:
            back = rng.randint(2, min(6, len(positions) - 1))
            t += rng.uniform(0.2, 0.8)
            again = positions[-back:]
            say([index.words[p] for p in again], list(again))
        if rng.random() < noise.restart:
            t += rng.uniform(0.4, 1.2)
            say([index.words[p] for p in positions], list(positions))
        if rng.random() < noise.filler:
            t += rng.uniform(0.2, 0.6)
            filler = rng.choice(FILLERS)
            say([filler], [None])
        t += rng.uniform(0.4, 1.5)  # the pause at the end of the ayah

    for n, verse in enumerate(range(first, last + 1)):
        if noise.fatiha_every and n % noise.fatiha_every == 0 and n:
            t += rng.uniform(15.0, 40.0)  # rukuʿ, sujud, standing up again
            for f in range(1, 8):
                ayah(f)
            say(["امين"], [None])
            t += rng.uniform(1.0, 2.0)
        ayah(verse)
    return out


@dataclass(frozen=True, slots=True)
class WordReport:
    letters: int  # letters with a truth word
    shown: float  # fraction of them with a word highlighted
    exact: float  # of those shown: the very word being recited
    near: float  # of those shown: within one word
    wrong: float  # of those shown: more than two words off (what must not happen)
    lag: float  # words behind the imam, on average, when shown and not wrong
    delay: float  # median seconds from a word's first letter to it being highlighted
    found: float  # fraction of recited words that were highlighted while recited (or soon after)
    anchors: int  # times the ayah tracker had to anchor (start, jumps, lost)


def run(
    tracker: WordTracker,
    letters: list[Letter],
    anchor_delay: float = 4.0,
    pause_after: float = 2.5,
) -> tuple[list[int | None], WordReport]:
    """Feed `letters` through `tracker`, anchored as the ayah tracker would; score it.

    A silence longer than `pause_after` seconds is reported with `pause()`, as
    the engine's voice detector would.

    A truth move back further than the tracker's window, or ahead, or into or
    out of al-Fatiha, is one the word tracker is not expected to follow: the
    ayah tracker re-anchors it.
    """
    jump = tracker.config.behind
    known = [(lt.time, lt.word) for lt in letters if lt.word is not None]

    def heard_at(time: float) -> int | None:
        last = None
        for t, w in known:
            if t > time:
                break
            last = w
        return last

    due: list[float] = []
    prev = None
    fatiha_end = tracker.index.verse_span(7)[1]
    for lt in letters:
        if lt.word is None:
            continue
        if prev is None or abs(lt.word - prev) > jump or (lt.word < fatiha_end) != (prev < fatiha_end):
            due.append(lt.time + anchor_delay)
        prev = lt.word

    tracker.reset()
    shown: list[int | None] = []
    anchors = 0
    first = len(letters)  # scored from the first anchor: before it is the ayah tracker's time
    lost_since: float | None = None
    last_time = None
    for i, lt in enumerate(letters):
        if last_time is not None and lt.time - last_time > pause_after:
            tracker.pause()
        last_time = lt.time
        while due and due[0] <= lt.time:
            at = heard_at(due.pop(0) - 2.0)
            if at is not None:
                tracker.anchor(at)
                anchors += 1
                first = min(first, i)
                lost_since = None
        st = tracker.feed(lt.ch)
        if st.status == LOST and lost_since is None:
            lost_since = lt.time
            if not due or due[0] > lt.time + anchor_delay:
                due.insert(0, lt.time + anchor_delay)
        shown.append(st.word if st.status == TRACKING else None)
    return shown, score(shown[first:], letters[first:], anchors)


def score(shown: list[int | None], letters: list[Letter], anchors: int = 0) -> WordReport:
    n = on = exact = near = wrong = 0
    lags: list[int] = []
    for s, lt in zip(shown, letters, strict=True):
        if lt.word is None:
            continue
        n += 1
        if s is None:
            continue
        on += 1
        exact += s == lt.word
        near += abs(s - lt.word) <= 1
        wrong += abs(s - lt.word) > 2
        if abs(s - lt.word) <= 2:
            lags.append(lt.word - s)

    # Each recited word (a run of letters with the same truth): when was it first highlighted?
    delays: list[float] = []
    words = 0
    i = 0
    while i < len(letters):
        w = letters[i].word
        if w is None:
            i += 1
            continue
        start = letters[i].time
        j = i
        while j < len(letters) and letters[j].word == w:
            j += 1
        words += 1
        k, until = i, start + 1.5
        while k < len(letters) and (k < j or letters[k].time <= until):
            if shown[k] == w:
                delays.append(letters[k].time - start)
                break
            k += 1
        i = j

    def frac(a: int, b: int) -> float:
        return a / b if b else 0.0

    return WordReport(
        letters=n,
        shown=frac(on, n),
        exact=frac(exact, on),
        near=frac(near, on),
        wrong=frac(wrong, on),
        lag=statistics.fmean(lags) if lags else 0.0,
        delay=statistics.median(delays) if delays else 0.0,
        found=frac(len(delays), words),
        anchors=anchors,
    )
