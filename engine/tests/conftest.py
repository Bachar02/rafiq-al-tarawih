"""Shared fixtures. The index and matcher are session-scoped: building them is
cheap (~0.1 s) but there is no reason to repeat it per test."""

from __future__ import annotations

import pytest

from rafiq.matching import Matcher, QuranIndex, get_index
from rafiq.quran import Quran, get_quran


@pytest.fixture(scope="session")
def q() -> Quran:
    return get_quran()


@pytest.fixture(scope="session")
def index() -> QuranIndex:
    return get_index()


@pytest.fixture(scope="session")
def matcher(index: QuranIndex) -> Matcher:
    return Matcher(index)


@pytest.fixture(scope="session")
def vid(q: Quran):
    """`vid(93, 2)` -> global verse id."""
    return lambda surah, ayah: q.verse(surah, ayah).id
