"""Put the on-device speech model into the app bundle.

Copies the trimmed, int8 Quran Whisper (built by trim_vocab.py into
build/whisper_onnx/) to mobile/assets/models/, under the names the app
expects, and writes manifest.json with each file's size and SHA-256. The app
copies these files to its own storage on first use, so Taraweeh mode works
offline from the first run.

The model files are not kept in git (55 MB). A release build must be made
after running this script; a build without it says it has no speech model.

    py tools/whisper_export/install_model.py           # copy and write the manifest
    py tools/whisper_export/install_model.py --check   # the bundle matches build/whisper_onnx
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "build" / "whisper_onnx"
TARGET = ROOT / "mobile" / "assets" / "models"

MODEL = "quran-basetrim"
# Bump when the model changes: the app then replaces its installed copy.
VERSION = 1
FILES = {
    "encoder.int8.onnx": f"{MODEL}-encoder.int8.onnx",
    "decoder.int8.onnx": f"{MODEL}-decoder.int8.onnx",
    "tokens.txt": f"{MODEL}-tokens.txt",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def manifest(directory: Path, names: dict[str, str]) -> dict:
    files = {}
    for target, source in names.items():
        path = directory / source
        files[target] = {"bytes": path.stat().st_size, "sha256": sha256(path)}
    return {"model": MODEL, "version": VERSION, "files": files}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    missing = [s for s in FILES.values() if not (SOURCE / s).exists()]
    if missing:
        print(f"missing in {SOURCE}: {missing}", file=sys.stderr)
        print("run export_quran_whisper.py, then trim_vocab.py", file=sys.stderr)
        return 1
    want = manifest(SOURCE, FILES)
    if args.check:
        path = TARGET / "manifest.json"
        have = json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
        bundled = all((TARGET / f).exists() for f in FILES)
        if have != want or not bundled:
            print("the bundled model is missing or stale; run install_model.py", file=sys.stderr)
            return 1
        print("bundled model is current")
        return 0
    TARGET.mkdir(parents=True, exist_ok=True)
    for target, source in FILES.items():
        shutil.copyfile(SOURCE / source, TARGET / target)
    text = json.dumps(want, indent=2) + "\n"
    (TARGET / "manifest.json").write_bytes(text.encode("utf-8"))
    total = sum(f["bytes"] for f in want["files"].values())
    print(f"{MODEL} v{VERSION}: {total / 1e6:.1f} MB in {TARGET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
