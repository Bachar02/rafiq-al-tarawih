"""The Quran as data: loading, lookup, and position arithmetic."""

from rafiq.quran.loader import QuranDataError, get_quran, load_quran
from rafiq.quran.model import Quran, Sajda, Surah, Verse

__all__ = ["Quran", "QuranDataError", "Sajda", "Surah", "Verse", "get_quran", "load_quran"]
