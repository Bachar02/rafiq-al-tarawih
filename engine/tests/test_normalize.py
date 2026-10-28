from __future__ import annotations

import pytest

from rafiq.normalize import normalize, tokenize


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # Uthmani diacritics, superscript alef and alef wasla all fold away.
        ("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ", "بسم الله الرحمن الرحيم"),
        # Hamza-bearing alefs -> bare alef.
        ("أإآا", "اااا"),
        # Alef maksura and teh marbuta fold to yeh and heh.
        ("على الصلاة", "علي الصلاه"),
        # Hamza on seats folds to the seat; a standalone hamza is dropped.
        ("مؤمن سئل السماء", "مومن سيل السما"),
        # Tatweel, punctuation, digits, Latin and ayah markers are word breaks.
        ("الحمـــد لله، رب ١ العالمين (2) abc ۝", "الحمد لله رب العالمين"),
        # Persian codepoints that some keyboards and models emit.
        ("کتاب ی", "كتاب ي"),
        ("", ""),
        ("   ", ""),
    ],
)
def test_normalize(raw: str, expected: str):
    assert normalize(raw) == expected


def test_normalize_is_idempotent(q):
    for verse in q.verses[:500]:
        once = normalize(verse.text)
        assert normalize(once) == once


def test_tokenize_splits_words():
    assert tokenize("  والضحى   والليل إذا سجى ") == ["والضحي", "والليل", "اذا", "سجي"]


def test_whole_quran_normalizes_to_bare_letters(q):
    allowed = set("ابتثجحخدذرزسشصضطظعغفقكلمنهوي ")
    leftovers = {ch for v in q for ch in normalize(v.text)} - allowed
    assert not leftovers, f"unexpected characters after normalization: {leftovers}"
