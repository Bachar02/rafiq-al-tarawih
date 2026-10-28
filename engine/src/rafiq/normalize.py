"""Arabic text normalization.

One function, `normalize`, is applied to *both* sides of every comparison: the
Quran index and whatever the ASR produces. The goal is recall, not
orthographic correctness — we fold together every distinction that an ASR model
(or a person typing on a phone) is likely to get wrong, because missing a match
costs far more than a slightly less discriminative index.

Rules live in plain tables so they can be audited and changed without touching
the logic. Changing them changes the index, so the matcher must be rebuilt —
`QuranIndex` always normalizes at construction time for exactly that reason.
"""

from __future__ import annotations

import re

# Harakat, Quranic annotation marks, superscript alef, small high/low signs.
_DIACRITICS = re.compile(
    "["
    "ؐ-ؚ"  # honorifics and small signs
    "ً-ٟ"  # fathatan .. wavy hamza below (all harakat, shadda, sukun)
    "ٰ"  # superscript alef
    "ۖ-ۭ"  # Quranic annotation signs
    "࣓-ࣿ"  # extended Arabic marks
    "]"
)

_TATWEEL = "ـ"

# Letter folding. Each key collapses into its value.
LETTER_MAP: dict[str, str] = {
    # alef variants -> bare alef
    "آ": "ا",  # آ
    "أ": "ا",  # أ
    "إ": "ا",  # إ
    "ٱ": "ا",  # ٱ alef wasla (Uthmani script)
    "ٲ": "ا",
    "ٳ": "ا",
    # hamza on a seat -> the seat
    "ؤ": "و",  # ؤ -> و
    "ئ": "ي",  # ئ -> ي
    # alef maksura -> yeh (ASR and keyboards confuse them constantly)
    "ى": "ي",  # ى -> ي
    # teh marbuta -> heh (pronounced as h in pause, which is how ayahs end)
    "ة": "ه",  # ة -> ه
    # Persian / Urdu codepoints that leak in from some keyboards and models
    "ک": "ك",  # ک -> ك
    "ی": "ي",  # ی -> ي
    "ہ": "ه",  # ہ -> ه
}

# Characters dropped outright. A standalone hamza is often omitted or written
# on a seat by ASR; dropping it makes both spellings agree.
DROP_CHARS = "ء"  # ء

_TRANSLATE = str.maketrans({**LETTER_MAP, **{c: None for c in DROP_CHARS + _TATWEEL}})

# After folding, anything that is not a basic Arabic letter becomes a word break:
# punctuation, digits, Latin, ayah-end markers.
_NON_ARABIC = re.compile("[^ء-ي]+")


def normalize(text: str) -> str:
    """Fold `text` to the canonical matching form: space-separated bare letters."""
    text = _DIACRITICS.sub("", text)
    text = text.translate(_TRANSLATE)
    return _NON_ARABIC.sub(" ", text).strip()


def tokenize(text: str) -> list[str]:
    """Normalize and split into words."""
    return normalize(text).split()
