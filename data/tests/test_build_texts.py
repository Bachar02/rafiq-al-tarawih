"""The translation pipeline refuses any text that does not line up with the Quran."""

from __future__ import annotations

import io
import json
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_texts as bt  # noqa: E402


def _rows() -> list[list]:
    out, i = [], 0
    for s, n in enumerate(bt.ayah_counts(), 1):
        for a in range(1, n + 1):
            i += 1
            out.append([str(i), str(s), str(a), f"text {s}:{a}", ""])
    return out


def _archive(rows: list[list]) -> bytes:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "x.sqlite"
        con = sqlite3.connect(path)
        con.execute("create table translations (id, sura, aya, translation, footnotes)")
        con.executemany("insert into translations values (?, ?, ?, ?, ?)", rows)
        con.commit()
        con.close()
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as z:
            z.write(path, "x.sqlite")
        return buf.getvalue()


def test_a_complete_text_is_read_verbatim():
    rows = _rows()
    rows[0][3] = "  In the name of Allah[1] "
    rows[0][4] = "[1] A note."
    out = bt.read_rows("t", _archive(rows))
    assert len(out) == bt.TOTAL_VERSES
    assert out[0] == ("  In the name of Allah[1] ", "[1] A note.")  # not even trimmed
    assert out[-1] == ("text 114:6", "")


def test_rows_out_of_storage_order_are_put_in_quran_order():
    rows = _rows()
    out = bt.read_rows("t", _archive(rows[::-1]))
    assert out[0][0] == "text 1:1"


@pytest.mark.parametrize(
    "damage",
    [
        lambda r: r.pop(),  # a missing ayah
        lambda r: r.__setitem__(7, [r[7][0], "2", "2", "x", ""]),  # 2:1 labelled 2:2
        lambda r: r.__setitem__(100, [*r[100][:3], "   ", ""]),  # an empty ayah
    ],
)
def test_a_damaged_text_aborts(damage):
    rows = _rows()
    damage(rows)
    with pytest.raises(bt.BuildError):
        bt.read_rows("t", _archive(rows))


def test_the_bundled_texts_are_pinned_and_built():
    """The committed assets are what the pinned archives produce."""
    files = bt.build(bt.load_manifest())
    for name, data in files.items():
        assert (bt.ASSET_DIR / name).read_bytes() == data, f"{name} is stale; run py data/build_texts.py"
    catalog = json.loads(files[bt.CATALOG])
    kinds = {(t["kind"], t["language"]) for t in catalog["texts"]}
    assert ("translation", "en") in kinds and ("tafsir", "ar") in kinds


def test_an_archive_that_is_not_the_pinned_one_aborts():
    manifest = bt.load_manifest()
    manifest["texts"][0]["sha256"] = "0" * 64
    with pytest.raises(bt.BuildError, match="SHA-256"):
        bt.build(manifest)
