"""The adhan recordings the Android app plays at prayer time.

One recording, dedicated to the public domain by its author:

    "Beautiful adhan.ogg", by Adam-synagda, 29 April 2022
    https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg
    Creative Commons CC0 1.0 Universal (Public Domain Dedication)
    Ogg Vorbis, 44.1 kHz stereo, 2 min 34 s: the whole adhan, twelve phrases.

Two files come from it, in mobile/android/app/src/main/res/raw/ (Android
plays a notification's sound from there):

    adhan_full.ogg    the recording itself, byte for byte (SHA-1 pinned below)
    adhan_takbir.ogg  its first two phrases, the four opening takbirs: the
                      same Vorbis packets up to the silence that follows them,
                      copied without decoding, so nothing is re-encoded

Usage:
    py data/build_adhan.py fetch   # download the recording again and check it
    py data/build_adhan.py         # cut adhan_takbir.ogg from adhan_full.ogg
    py data/build_adhan.py --check # CI: the recording is the pinned one

The cut needs PyAV (`pip install av`); the check needs nothing.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "mobile" / "android" / "app" / "src" / "main" / "res" / "raw"
FULL = RAW_DIR / "adhan_full.ogg"
TAKBIR = RAW_DIR / "adhan_takbir.ogg"

SOURCE = "https://upload.wikimedia.org/wikipedia/commons/b/b0/Beautiful_adhan.ogg"
SHA1 = "a1fa4fd942401922c5c3301816384aae86956522"
USER_AGENT = "rafiq-build (Quran reader; bundles a public-domain adhan recording)"

# The second phrase ends at 30.7 s and the third begins at 31.7 s: the cut
# falls in the silence between them.
TAKBIR_SECONDS = 31.2


class BuildError(Exception):
    """A source inconsistency. Always fatal."""


def sha1(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def check() -> None:
    if not FULL.exists():
        raise BuildError(f"{FULL} is missing: run `py data/build_adhan.py fetch`")
    if sha1(FULL) != SHA1:
        raise BuildError(f"{FULL.name} is not the pinned recording (SHA-1 {sha1(FULL)})")
    if not TAKBIR.exists():
        raise BuildError(f"{TAKBIR} is missing: run `py data/build_adhan.py`")


def fetch() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(SOURCE, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request) as response:
        data = response.read()
    digest = hashlib.sha1(data).hexdigest()
    if digest != SHA1:
        raise BuildError(f"the recording at {SOURCE} changed (SHA-1 {digest}): review it before pinning it")
    FULL.write_bytes(data)
    print(f"{FULL.name}: {len(data):,} bytes")


def build() -> None:
    if not FULL.exists() or sha1(FULL) != SHA1:
        raise BuildError(f"{FULL.name} is missing or is not the pinned recording: run `fetch` first")
    try:
        import av
    except ImportError as e:
        raise BuildError("cutting the takbir needs PyAV: pip install av") from e

    with av.open(str(FULL)) as source, av.open(str(TAKBIR), "w", format="ogg") as target:
        stream = source.streams.audio[0]
        if stream.codec_context.name != "vorbis":
            raise BuildError(f"expected Vorbis audio, found {stream.codec_context.name}")
        out = target.add_stream_from_template(stream)
        for packet in source.demux(stream):
            if packet.dts is None:  # the flush packet at the end
                continue
            if packet.pts * stream.time_base >= TAKBIR_SECONDS:
                break
            packet.stream = out
            target.mux(packet)

    with av.open(str(TAKBIR)) as result:
        seconds = float(result.duration) / 1_000_000
    if abs(seconds - TAKBIR_SECONDS) > 0.5:
        raise BuildError(f"{TAKBIR.name} lasts {seconds:.1f} s, not about {TAKBIR_SECONDS} s")
    print(f"{TAKBIR.name}: {TAKBIR.stat().st_size:,} bytes, {seconds:.1f} s")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", nargs="?", choices=["build", "fetch"], default="build")
    parser.add_argument("--check", action="store_true", help="only verify the bundled recording")
    args = parser.parse_args()
    try:
        if args.check:
            check()
        elif args.command == "fetch":
            fetch()
        else:
            build()
    except BuildError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
