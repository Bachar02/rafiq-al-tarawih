"""Synthetic recitation streams, as an ASR would transcribe them.

Until real recordings exist (Phase 2), this is how the matcher and tracker are
exercised end to end. It models what actually goes wrong in a mosque at the text
level: chunks of a few words, misheard letters, dropped and spurious words, an
ayah repeated by the imam, al-Fatiha at the start of each rak'ah, and chunks of
noise that match nothing.

Every step carries the ground truth, so the same stream feeds both the
evaluation harness and the playground's replay view.
"""

from __future__ import annotations

import random
from dataclasses import asdict, dataclass

from rafiq.matching.index import QuranIndex

# Letters an Arabic ASR commonly confuses (emphatic/plain pairs, similar sounds).
CONFUSABLE: dict[str, str] = {
    "ض": "د", "د": "ض", "ظ": "ذ", "ذ": "ز", "ز": "ذ", "ص": "س", "س": "ص",
    "ط": "ت", "ت": "ط", "ح": "ه", "ه": "ح", "ق": "ك", "ك": "ق", "ع": "ا",
    "ث": "س", "غ": "خ", "خ": "غ",
}  # fmt: skip


@dataclass(frozen=True, slots=True)
class NoiseConfig:
    min_chunk: int = 3  # words per ASR chunk
    max_chunk: int = 8
    word_corrupt: float = 0.10  # probability a word gets a letter-level error
    word_drop: float = 0.05
    word_insert: float = 0.03
    repeat_ayah: float = 0.03  # probability the imam repeats the ayah just finished
    garbage_chunk: float = 0.03  # chunk of noise (coughs, "amin", crosstalk)
    fatiha_every: int = 0  # insert al-Fatiha every N ayahs (a rak'ah); 0 disables
    basmala: bool = True  # recite the basmala (al-Fatiha 1:1) before each surah that has one

    @classmethod
    def clean(cls) -> NoiseConfig:
        return cls(word_corrupt=0, word_drop=0, word_insert=0, repeat_ayah=0, garbage_chunk=0)

    @classmethod
    def preset(cls, name: str) -> NoiseConfig:
        presets = {
            "clean": cls.clean(),
            "light": cls(),
            "heavy": cls(word_corrupt=0.25, word_drop=0.10, word_insert=0.06, garbage_chunk=0.08),
        }
        return presets[name]


@dataclass(frozen=True, slots=True)
class Step:
    text: str
    truth_verse: int | None  # verse id of the last recited word; None for a noise chunk
    truth_word: int | None  # stream position of the last recited word
    spoken: tuple[int, ...] = ()  # every verse id heard in this chunk, in order

    def to_dict(self) -> dict:
        return asdict(self)


def simulate(
    index: QuranIndex,
    start_verse: int,
    end_verse: int,
    noise: NoiseConfig = NoiseConfig(),
    seed: int = 0,
) -> list[Step]:
    """Recite verses `start_verse..end_verse` (global ids, inclusive) as noisy chunks."""
    rng = random.Random(seed)
    spoken = _recitation_order(index, start_verse, end_verse, noise, rng)

    steps: list[Step] = []
    i = 0
    while i < len(spoken):
        if rng.random() < noise.garbage_chunk:
            steps.append(Step(_garbage(index, rng), None, None))
        size = rng.randint(noise.min_chunk, noise.max_chunk)
        chunk = spoken[i : i + size]
        i += size
        words = _corrupt([index.words[p] for p in chunk], index, noise, rng)
        if words:
            last = chunk[-1]
            heard = tuple(dict.fromkeys(index.word_verse[p] for p in chunk))
            steps.append(Step(" ".join(words), index.word_verse[last], last, heard))
    return steps


def _recitation_order(
    index: QuranIndex, start_verse: int, end_verse: int, noise: NoiseConfig, rng: random.Random
) -> list[int]:
    """Stream positions in the order the imam says them."""
    quran = index.quran
    fatiha = [p for v in range(1, 8) for p in range(*index.verse_span(v))]
    basmala = list(range(*index.verse_span(1)))
    order: list[int] = []
    for n, verse in enumerate(range(start_verse, end_verse + 1)):
        if noise.fatiha_every and n % noise.fatiha_every == 0:
            order.extend(fatiha)
        v = quran.by_id(verse)
        if noise.basmala and v.ayah == 1 and quran.surah(v.surah).has_basmala:
            order.extend(basmala)
        span = list(range(*index.verse_span(verse)))
        order.extend(span)
        if rng.random() < noise.repeat_ayah:
            order.extend(span)
    return order


def _corrupt(words: list[str], index: QuranIndex, noise: NoiseConfig, rng: random.Random) -> list[str]:
    out: list[str] = []
    for word in words:
        if rng.random() < noise.word_drop:
            continue
        if rng.random() < noise.word_corrupt:
            word = _misspell(word, rng)
        out.append(word)
        if rng.random() < noise.word_insert:
            out.append(rng.choice(index.vocab))
    return out


def _misspell(word: str, rng: random.Random) -> str:
    chars = list(word)
    i = rng.randrange(len(chars))
    if chars[i] in CONFUSABLE and rng.random() < 0.7:
        chars[i] = CONFUSABLE[chars[i]]
    elif len(chars) > 2:
        del chars[i]
    return "".join(chars)


def _garbage(index: QuranIndex, rng: random.Random) -> str:
    return " ".join(rng.choice(index.vocab) for _ in range(rng.randint(1, 3)))
