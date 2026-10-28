"""Dataset integrity and the position arithmetic the tracker will depend on.

`build_quran.py` already cross-checks the Tanzil text against the Tanzil
metadata. These tests add a third, independent source: the canonical Hafs ayah
counts, written out by hand below. If the shipped dataset ever silently changes
variant, gets truncated, or is rebuilt from a different edition, this table is
what notices.
"""

from __future__ import annotations

import re

import pytest

from rafiq.quran import Quran, QuranDataError, load_quran

# Canonical ayah count per surah, Hafs 'an Asim, surahs 1..114.
CANONICAL_AYAH_COUNTS = [
    7,
    286,
    200,
    176,
    120,
    165,
    206,
    75,
    129,
    109,
    123,
    111,
    43,
    52,
    99,
    128,
    111,
    110,
    98,
    135,
    112,
    78,
    118,
    64,
    77,
    227,
    93,
    88,
    69,
    60,
    34,
    30,
    73,
    54,
    45,
    83,
    182,
    88,
    75,
    85,
    54,
    53,
    89,
    59,
    37,
    35,
    38,
    29,
    18,
    45,
    60,
    49,
    62,
    55,
    78,
    96,
    29,
    22,
    24,
    13,
    14,
    11,
    11,
    18,
    12,
    12,
    30,
    52,
    52,
    44,
    28,
    28,
    20,
    56,
    40,
    31,
    50,
    40,
    46,
    42,
    29,
    19,
    36,
    25,
    22,
    17,
    19,
    26,
    30,
    20,
    15,
    21,
    11,
    8,
    8,
    19,
    5,
    8,
    8,
    11,
    11,
    8,
    3,
    9,
    5,
    4,
    7,
    3,
    6,
    3,
    5,
    4,
    5,
    6,
]

# Combining marks that Simple Clean is defined to have removed: the tashkeel
# block, superscript alef, and the Quranic annotation signs.
DIACRITICS = re.compile(r"[ً-ْٰۖ-ۭ]")


@pytest.fixture(scope="module")
def quran() -> Quran:
    return load_quran()


# -- the fixture itself -------------------------------------------------


def test_canonical_table_is_self_consistent():
    """Guard the guard: a mistyped table would weaken every test below."""
    assert len(CANONICAL_AYAH_COUNTS) == 114
    assert sum(CANONICAL_AYAH_COUNTS) == 6236


# -- shape --------------------------------------------------------------


def test_verse_and_surah_totals(quran: Quran):
    assert len(quran) == 6236
    assert len(quran.surahs) == 114


def test_ayah_counts_match_canonical(quran: Quran):
    actual = [s.ayah_count for s in quran.surahs]
    assert actual == CANONICAL_AYAH_COUNTS


def test_ayah_counts_match_actual_verses(quran: Quran):
    """Metadata could agree with the table while the text is short."""
    for surah in quran.surahs:
        assert len(quran.surah_verses(surah.index)) == surah.ayah_count


def test_global_ids_are_contiguous(quran: Quran):
    assert [v.id for v in quran] == list(range(1, 6237))


def test_surah_offsets_align_with_ids(quran: Quran):
    for surah in quran.surahs:
        first = quran.verse(surah.index, 1)
        last = quran.verse(surah.index, surah.ayah_count)
        assert first.id == surah.first_verse_id
        assert last.id == surah.last_verse_id


def test_ayahs_numbered_from_one_within_each_surah(quran: Quran):
    for surah in quran.surahs:
        verses = quran.surah_verses(surah.index)
        assert [v.ayah for v in verses] == list(range(1, surah.ayah_count + 1))


def test_no_verse_is_empty(quran: Quran):
    assert all(v.text.strip() for v in quran)


def test_text_variant_is_undiacritised(quran: Quran):
    """Matching assumes Simple Clean. Uthmani text here would break the matcher
    subtly rather than loudly, so assert the variant directly."""
    offenders = [v.ref for v in quran if DIACRITICS.search(v.text)]
    assert not offenders, f"unexpected diacritics in {len(offenders)} verses, e.g. {offenders[:5]}"


def test_character_inventory_is_closed(quran: Quran):
    """The corpus uses exactly these 37 characters — no diacritics, but every
    hamza form, alef maqsura and ta marbuta is present and *unfolded*.

    This is the specification the Phase 1 normalizer has to meet: ASR output
    will not reliably distinguish أ / إ / آ / ا, nor ى / ي, nor ة / ه, so the
    matching index must fold them. Pinning the inventory here means that if the
    dataset ever changes shape underneath the normalizer, this fails first.
    """
    expected = set(" ءآأؤإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىي")
    actual = {ch for v in quran for ch in v.text}
    assert actual == expected


# -- known content ------------------------------------------------------


def test_endpoints(quran: Quran):
    first, last = quran.by_id(1), quran.by_id(6236)
    assert (first.surah, first.ayah) == (1, 1)
    assert (last.surah, last.ayah) == (114, 6)


def test_known_verse_text(quran: Quran):
    assert quran.verse(1, 1).text == "بسم الله الرحمن الرحيم"
    assert quran.verse(93, 2).text == "والليل إذا سجى"
    assert quran.verse(93, 1).text == "والضحى"


BASMALA = "بسم الله الرحمن الرحيم"


def test_basmala_is_split_from_first_ayahs(quran: Quran):
    """Only al-Fatiha 1:1 is the basmala itself; elsewhere it is a surah flag."""
    starting = [v.ref for v in quran if v.text.startswith(BASMALA)]
    assert starting == ["1:1"]
    assert BASMALA in quran.verse(27, 30).text  # the one mid-surah occurrence stays
    flagged = [s.index for s in quran.surahs if s.has_basmala]
    assert flagged == [i for i in range(2, 115) if i != 9]


def test_surah_metadata(quran: Quran):
    duha = quran.surah(93)
    assert duha.name_ar == "الضحى"
    assert duha.ayah_count == 11
    assert duha.revelation_type == "Meccan"

    baqara = quran.surah(2)
    assert baqara.name_translit == "Al-Baqara"
    assert baqara.revelation_type == "Medinan"


def test_ref_formatting(quran: Quran):
    assert quran.verse(93, 2).ref == "93:2"


# -- lookup errors ------------------------------------------------------


@pytest.mark.parametrize("surah,ayah", [(93, 12), (115, 1), (0, 1), (2, 0)])
def test_missing_verse_raises(quran: Quran, surah: int, ayah: int):
    with pytest.raises(KeyError):
        quran.verse(surah, ayah)


@pytest.mark.parametrize("bad_id", [0, -1, 6237])
def test_out_of_range_id_raises(quran: Quran, bad_id: int):
    with pytest.raises(KeyError):
        quran.by_id(bad_id)


# -- position arithmetic ------------------------------------------------


def test_window_crosses_surah_boundary(quran: Quran):
    """The imam runs 93:11 straight into 94:1; windows must not stop at the seam."""
    end_of_duha = quran.verse(93, 11)
    window = quran.window(end_of_duha.id, 3)
    assert [v.ref for v in window] == ["93:11", "94:1", "94:2"]


def test_window_clips_at_the_end(quran: Quran):
    assert [v.ref for v in quran.window(6235, 10)] == ["114:5", "114:6"]


def test_window_of_nonpositive_length_is_empty(quran: Quran):
    assert quran.window(100, 0) == []


def test_distance_is_signed_and_in_ayahs(quran: Quran):
    assert quran.distance((93, 5), (93, 6)) == 1
    assert quran.distance((93, 6), (93, 5)) == -1
    assert quran.distance((93, 5), (93, 5)) == 0


def test_distance_separates_near_miss_from_catastrophe(quran: Quran):
    """The metric's whole purpose: 93:6 for 93:5 is a near miss, 2:255 is not."""
    near = abs(quran.distance((93, 5), (93, 6)))
    far = abs(quran.distance((93, 5), (2, 255)))
    assert near == 1
    assert far > 1000


# -- structural markers -------------------------------------------------


def test_juz_boundaries(quran: Quran):
    assert quran.juz_of(quran.verse(1, 1).id) == 1
    assert quran.juz_of(quran.verse(2, 141).id) == 1
    assert quran.juz_of(quran.verse(2, 142).id) == 2
    assert quran.juz_of(quran.verse(78, 1).id) == 30
    assert quran.juz_of(quran.verse(114, 6).id) == 30


def test_juz_span(quran: Quran):
    assert quran.juz_span(1) == (1, quran.verse(2, 141).id)
    assert quran.juz_span(30) == (quran.verse(78, 1).id, 6236)
    covered = sum(b - a + 1 for a, b in (quran.juz_span(i) for i in range(1, 31)))
    assert covered == 6236


def test_sajdas(quran: Quran):
    assert len(quran.sajdas) == 15
    assert quran.sajda_at(7, 206) is not None
    assert quran.sajda_at(93, 2) is None


# -- loader errors ------------------------------------------------------


def test_missing_dataset_message_says_how_to_build(tmp_path):
    with pytest.raises(QuranDataError, match=r"build_quran\.py"):
        load_quran(tmp_path / "nope.json")


def test_malformed_dataset_is_reported(tmp_path):
    bad = tmp_path / "quran.json"
    bad.write_text("{not json", encoding="utf-8")
    with pytest.raises(QuranDataError, match="not valid JSON"):
        load_quran(bad)


def test_wrong_shape_is_reported(tmp_path):
    bad = tmp_path / "quran.json"
    bad.write_text('{"verses": [], "surahs": []}', encoding="utf-8")
    with pytest.raises(QuranDataError, match="unexpected shape"):
        load_quran(bad)
