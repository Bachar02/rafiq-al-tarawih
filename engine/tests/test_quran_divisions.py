"""Page and hizb-quarter marks in `quran.json`, which the app navigates by.

`build_quran.py` checks that the marks form complete, ordered partitions of
the text. These tests add independent knowledge: where well-known passages
fall in the printed Madinah mushaf (604 pages), written out by hand below. If
the dataset were rebuilt from a different edition's page table, a reader
would land on the wrong page with no visible error; this is what notices.
"""

from __future__ import annotations

import bisect
import copy
import importlib.util
import json
from pathlib import Path

import pytest

from rafiq.quran.loader import find_quran_json

ROOT = Path(__file__).resolve().parents[2]

# The page each juz starts on in the Madinah mushaf. Twenty pages per juz,
# except juz 7 (page 121) and juz 11 (page 201), as printed.
JUZ_START_PAGES = [1, 22, 42, 62, 82, 102, 121, 142, 162, 182, 201, 222, 242, 262, 282]
JUZ_START_PAGES += [302, 322, 342, 362, 382, 402, 422, 442, 462, 482, 502, 522, 542, 562, 582]

# (surah, ayah) -> page, for passages readers look up by page.
KNOWN_PAGES = {
    (1, 1): 1,
    (2, 1): 2,
    (2, 255): 42,  # Ayat al-Kursi
    (18, 1): 293,  # al-Kahf
    (36, 1): 440,  # Ya-Sin
    (55, 1): 531,  # ar-Rahman
    (67, 1): 562,  # al-Mulk
    (78, 1): 582,  # an-Naba'
    (112, 1): 604,
    (114, 6): 604,
}


@pytest.fixture(scope="module")
def payload() -> dict:
    return json.loads(find_quran_json().read_text(encoding="utf-8"))


def _verse_id(payload: dict, surah: int, ayah: int) -> int:
    return payload["surahs"][surah - 1]["first_verse_id"] + ayah - 1


def _starts(payload: dict, key: str) -> list[int]:
    return [_verse_id(payload, m["surah"], m["ayah"]) for m in payload[key]]


def test_counts(payload: dict):
    assert len(payload["pages"]) == 604
    assert len(payload["hizb_quarters"]) == 240


def test_juz_start_pages(payload: dict):
    pages = _starts(payload, "pages")
    juz_pages = [bisect.bisect_right(pages, v) for v in _starts(payload, "juzs")]
    assert juz_pages == JUZ_START_PAGES


def test_known_pages(payload: dict):
    pages = _starts(payload, "pages")
    for (surah, ayah), page in KNOWN_PAGES.items():
        assert bisect.bisect_right(pages, _verse_id(payload, surah, ayah)) == page, f"{surah}:{ayah}"


def test_every_juz_is_eight_quarters(payload: dict):
    quarters = _starts(payload, "hizb_quarters")
    assert _starts(payload, "juzs") == quarters[::8]


def test_existing_fields_are_unchanged_by_the_new_marks(payload: dict):
    """Pages and quarters were added later: verse ids and juzs must not move."""
    assert len(payload["verses"]) == 6236
    assert [v["id"] for v in payload["verses"]] == list(range(1, 6237))
    assert payload["juzs"][1] == {"index": 2, "surah": 2, "ayah": 142}


# -- the build refuses bad marks -------------------------------------------


@pytest.fixture(scope="module")
def build_module():
    spec = importlib.util.spec_from_file_location("build_quran", ROOT / "data" / "build_quran.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def sources(build_module):
    verses = build_module.parse_text(build_module.TEXT_SRC)
    meta = build_module.parse_metadata(build_module.META_SRC)
    build_module.validate(verses, meta)  # the real data passes
    return verses, meta


@pytest.mark.parametrize(
    ("key", "mutate", "message"),
    [
        ("pages", lambda marks: marks.pop(), "604"),
        ("pages", lambda marks: marks.__setitem__(10, dict(marks[9], index=11)), "does not follow"),
        ("hizb_quarters", lambda marks: marks[5].update(ayah=999), "nonexistent"),
        ("hizb_quarters", lambda marks: marks[8].update(ayah=marks[8]["ayah"] + 1), "juz 2"),
    ],
)
def test_build_rejects_corrupted_marks(build_module, sources, key, mutate, message):
    verses, meta = sources
    bad = copy.deepcopy(meta)
    mutate(bad[key])
    with pytest.raises(build_module.BuildError, match=message):
        build_module.validate_divisions(verses, bad)
