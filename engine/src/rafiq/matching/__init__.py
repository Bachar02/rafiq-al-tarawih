"""Text -> candidate positions in the Quran."""

from rafiq.matching.align import AlignConfig, Alignment, align
from rafiq.matching.index import QuranIndex, get_index
from rafiq.matching.matcher import Match, MatchConfig, Matcher

__all__ = [
    "AlignConfig",
    "Alignment",
    "Match",
    "MatchConfig",
    "Matcher",
    "QuranIndex",
    "align",
    "get_index",
]
