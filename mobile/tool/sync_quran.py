"""Copy the Quran dataset from the data pipeline into the app's assets.

The app bundles data/quran.json (built by data/build_quran.py from the
verbatim Tanzil sources) so it works offline. This keeps the two in sync:

    py data/build_quran.py && py mobile/tool/sync_quran.py          # update the asset
    py mobile/tool/sync_quran.py --check                            # CI: fail if stale
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "data" / "quran.json"
TARGET = ROOT / "mobile" / "assets" / "quran" / "quran.json"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="exit 1 if the asset differs from the pipeline output")
    args = ap.parse_args()

    if not SOURCE.exists():
        print(f"{SOURCE} not found; run: py data/build_quran.py", file=sys.stderr)
        return 1
    data = SOURCE.read_bytes()
    if args.check:
        if not TARGET.exists() or TARGET.read_bytes() != data:
            print(f"{TARGET} is stale; run: py mobile/tool/sync_quran.py", file=sys.stderr)
            return 1
        print("quran asset is up to date")
        return 0
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_bytes(data)
    print(f"wrote {TARGET} ({len(data) / 1e6:.2f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
