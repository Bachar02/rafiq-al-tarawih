"""In-memory Quran model.

The central idea here is the **global verse id**: every ayah has an id from 1
(al-Fatiha 1:1) to 6236 (an-Nas 114:6). Two things fall out of that, and both
matter more than they look:

1. Sliding windows over the recitation cross surah boundaries for free. An imam
   moving from 93:11 into 94:1 is just id 6101 -> 6102, no special case.
2. "How wrong was this prediction?" becomes integer subtraction. Confusing
   93:5 with 93:6 scores 1; confusing it with 2:255 scores 3830. Any metric
   that treats those alike would hide the difference between a system that is
   nearly right and one that is lost.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Verse:
    id: int  # global 1-based index, 1..6236
    surah: int
    ayah: int
    text: str

    @property
    def ref(self) -> str:
        """Canonical reference, e.g. `93:2`."""
        return f"{self.surah}:{self.ayah}"

    def __str__(self) -> str:
        return f"{self.ref} {self.text}"


@dataclass(frozen=True, slots=True)
class Surah:
    index: int
    name_ar: str
    name_translit: str
    name_en: str
    ayah_count: int
    revelation_type: str  # "Meccan" | "Medinan"
    revelation_order: int
    rukus: int
    first_verse_id: int
    has_basmala: bool = False  # recited before ayah 1 (not part of it); false for 1 and 9

    @property
    def last_verse_id(self) -> int:
        return self.first_verse_id + self.ayah_count - 1


@dataclass(frozen=True, slots=True)
class Sajda:
    index: int
    surah: int
    ayah: int
    type: str  # "recommended" | "obligatory"


class Quran:
    """The full text plus its structural metadata.

    Immutable in practice and cheap to hold: the whole thing is about a
    megabyte, so on-device use never needs a database.
    """

    def __init__(
        self,
        verses: list[Verse],
        surahs: list[Surah],
        juzs: list[tuple[int, int, int]],
        sajdas: list[Sajda],
    ) -> None:
        self._verses = verses
        self._surahs = surahs
        self._juzs = juzs  # (index, surah, ayah)
        self._sajdas = sajdas
        self._by_ref = {(v.surah, v.ayah): v for v in verses}
        self._sajda_refs = {(s.surah, s.ayah): s for s in sajdas}

    # -- basics ----------------------------------------------------------

    def __len__(self) -> int:
        return len(self._verses)

    def __iter__(self) -> Iterator[Verse]:
        return iter(self._verses)

    @property
    def verses(self) -> list[Verse]:
        return self._verses

    @property
    def surahs(self) -> list[Surah]:
        return self._surahs

    @property
    def sajdas(self) -> list[Sajda]:
        return self._sajdas

    # -- lookup ----------------------------------------------------------

    def verse(self, surah: int, ayah: int) -> Verse:
        try:
            return self._by_ref[(surah, ayah)]
        except KeyError:
            raise KeyError(f"no such verse: {surah}:{ayah}") from None

    def by_id(self, verse_id: int) -> Verse:
        if not 1 <= verse_id <= len(self._verses):
            raise KeyError(f"verse id out of range: {verse_id}")
        return self._verses[verse_id - 1]

    def surah(self, index: int) -> Surah:
        if not 1 <= index <= len(self._surahs):
            raise KeyError(f"no such surah: {index}")
        return self._surahs[index - 1]

    def surah_verses(self, index: int) -> list[Verse]:
        s = self.surah(index)
        return self._verses[s.first_verse_id - 1 : s.last_verse_id]

    def sajda_at(self, surah: int, ayah: int) -> Sajda | None:
        """The prostration marker at this ayah, if any — a UI cue during recitation."""
        return self._sajda_refs.get((surah, ayah))

    def juz_of(self, verse_id: int) -> int:
        """Which juz a verse falls in. Taraweeh is often one juz per night, which
        makes this a useful prior on where the imam is likely to be."""
        verse = self.by_id(verse_id)
        current = 1
        for index, surah, ayah in self._juzs:
            if (surah, ayah) > (verse.surah, verse.ayah):
                break
            current = index
        return current

    def juz_span(self, index: int) -> tuple[int, int]:
        """First and last verse id of a juz (1..30)."""
        if not 1 <= index <= len(self._juzs):
            raise KeyError(f"no such juz: {index}")
        _, surah, ayah = self._juzs[index - 1]
        first = self.verse(surah, ayah).id
        if index == len(self._juzs):
            return first, len(self._verses)
        _, next_surah, next_ayah = self._juzs[index]
        return first, self.verse(next_surah, next_ayah).id - 1

    # -- position arithmetic ---------------------------------------------

    def window(self, start_id: int, length: int) -> list[Verse]:
        """`length` consecutive verses from `start_id`, clipped at the ends.

        Crosses surah boundaries deliberately: the imam does too.
        """
        if length <= 0:
            return []
        start = max(1, start_id)
        return self._verses[start - 1 : start - 1 + length]

    def distance(self, a: Verse | tuple[int, int], b: Verse | tuple[int, int]) -> int:
        """Signed distance in ayahs, `b - a`. The basis of the position-error metric."""
        return self._resolve_id(b) - self._resolve_id(a)

    def _resolve_id(self, ref: Verse | tuple[int, int]) -> int:
        if isinstance(ref, Verse):
            return ref.id
        return self.verse(*ref).id
