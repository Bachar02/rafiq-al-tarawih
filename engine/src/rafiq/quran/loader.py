"""Load `data/quran.json` into a `Quran`.

The file is a build artifact rather than a checked-in blob, so the loader's main
job when things go wrong is to say *how to produce it* instead of raising a bare
FileNotFoundError at some unrelated call site.
"""

from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path

from rafiq.quran.model import Quran, Sajda, Surah, Verse

ENV_VAR = "RAFIQ_QURAN_JSON"
_RELATIVE = Path("data") / "quran.json"


class QuranDataError(RuntimeError):
    """The dataset is missing or unusable."""


def find_quran_json(explicit: Path | None = None) -> Path:
    """Locate quran.json: explicit path, then $RAFIQ_QURAN_JSON, then by walking up.

    Walking up from this file lets the engine work identically when installed
    editable from a checkout, run from a subdirectory, or imported by the
    server — none of which share a working directory.
    """
    if explicit is not None:
        return Path(explicit)
    if env := os.environ.get(ENV_VAR):
        return Path(env)
    for parent in Path(__file__).resolve().parents:
        candidate = parent / _RELATIVE
        if candidate.exists():
            return candidate
    return Path(__file__).resolve().parents[4] / _RELATIVE  # best guess, for the error message


def load_quran(path: Path | None = None) -> Quran:
    """Read the dataset. Prefer `get_quran()` unless you need a specific file."""
    resolved = find_quran_json(path)
    if not resolved.exists():
        raise QuranDataError(
            f"Quran dataset not found at {resolved}.\n"
            f"Build it with:  py data/build_quran.py\n"
            f"(or point {ENV_VAR} at an existing quran.json)"
        )

    try:
        payload = json.loads(resolved.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise QuranDataError(f"{resolved} is not valid JSON ({e}); rebuild with data/build_quran.py") from e

    try:
        verses = [Verse(**v) for v in payload["verses"]]
        surahs = [Surah(**s) for s in payload["surahs"]]
        juzs = [(j["index"], j["surah"], j["ayah"]) for j in payload["juzs"]]
        sajdas = [Sajda(**s) for s in payload["sajdas"]]
    except (KeyError, TypeError) as e:
        raise QuranDataError(
            f"{resolved} has an unexpected shape ({e}); it may predate the current "
            f"build script. Rebuild with data/build_quran.py"
        ) from e

    return Quran(verses=verses, surahs=surahs, juzs=juzs, sajdas=sajdas)


@lru_cache(maxsize=1)
def get_quran() -> Quran:
    """The shared, lazily-loaded dataset. Parsing costs ~1 MB of JSON, so callers
    that need it repeatedly (the matcher, the tracker, every request) share one."""
    return load_quran()
