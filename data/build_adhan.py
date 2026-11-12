"""The adhan recordings the Android app plays at prayer time.

The source is data/adhan/adhan.mp3, the recording the app's owner chose for
every prayer (SHA-1 pinned below; its origin is in
mobile/assets/adhan/NOTICE.txt): MP3, 16 kHz mono, 2 min 32 s, twelve
phrases.

Two files are made from it, in mobile/android/app/src/main/res/raw/ (Android
plays a notification's sound from there, by name, so these names stay):

    adhan_full.mp3    the whole adhan, raised to a peak of -1 dBFS: the
                      recording peaks at -18 dBFS, too quiet for a phone
                      (a notification plays at the notification volume)
    adhan_takbir.mp3  its first two phrases, the four opening takbirs, cut
                      in the silence that follows them, with a short fade

Usage:
    py data/build_adhan.py          # make both files from the source
    py data/build_adhan.py --check  # CI: the source is the pinned one, both files exist

Making them needs PyAV and numpy (`pip install av numpy`); the check needs
nothing.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "adhan" / "adhan.mp3"
SHA1 = "db4e5f8390785e544bcdd2a317f68c1709de092e"
RAW_DIR = ROOT / "mobile" / "android" / "app" / "src" / "main" / "res" / "raw"
FULL = RAW_DIR / "adhan_full.mp3"
TAKBIR = RAW_DIR / "adhan_takbir.mp3"

# The second phrase ends at 24.5 s and the third begins at 27.4 s: the cut
# falls in the silence between them.
TAKBIR_SECONDS = 26.0
FADE_SECONDS = 0.3
PEAK_DBFS = -1.0
BITRATE = 32_000


class BuildError(Exception):
    """A source inconsistency. Always fatal."""


def sha1(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def check() -> None:
    if not SOURCE.exists():
        raise BuildError(f"{SOURCE} is missing")
    if sha1(SOURCE) != SHA1:
        raise BuildError(f"{SOURCE.name} is not the pinned recording (SHA-1 {sha1(SOURCE)})")
    for path in (FULL, TAKBIR):
        if not path.exists():
            raise BuildError(f"{path} is missing: run `py data/build_adhan.py`")
    # Android refuses two raw resources of the same name.
    names = [p.stem for p in RAW_DIR.iterdir() if p.suffix != ".xml"]
    if len(names) != len(set(names)):
        raise BuildError(f"two raw resources share a name in {RAW_DIR}: {sorted(names)}")


def build() -> None:
    if not SOURCE.exists() or sha1(SOURCE) != SHA1:
        raise BuildError(f"{SOURCE} is missing or is not the pinned recording")
    try:
        import av
        import numpy as np
    except ImportError as e:
        raise BuildError("making the files needs PyAV and numpy: pip install av numpy") from e

    with av.open(str(SOURCE)) as source:
        stream = source.streams.audio[0]
        rate = stream.rate
        resampler = av.AudioResampler(format="flt", layout="mono", rate=rate)
        chunks = [
            resampled.to_ndarray().reshape(-1)
            for frame in source.decode(stream)
            for resampled in resampler.resample(frame)
        ]
    samples = np.concatenate(chunks).astype(np.float32)
    peak = float(np.abs(samples).max())
    if peak <= 0:
        raise BuildError(f"{SOURCE.name} is silent")
    samples *= 10 ** (PEAK_DBFS / 20) / peak

    def write(path: Path, x: np.ndarray) -> None:
        with av.open(str(path), "w", format="mp3") as target:
            out = target.add_stream("libmp3lame", rate=rate)
            out.layout = "mono"
            out.bit_rate = BITRATE
            frame = av.AudioFrame.from_ndarray(x.reshape(1, -1), format="flt", layout="mono")
            frame.sample_rate = rate
            for packet in out.encode(frame):
                target.mux(packet)
            for packet in out.encode(None):
                target.mux(packet)
        print(f"{path.name}: {path.stat().st_size:,} bytes, {len(x) / rate:.1f} s")

    write(FULL, samples)
    takbir = samples[: int(TAKBIR_SECONDS * rate)].copy()
    fade = int(FADE_SECONDS * rate)
    takbir[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)
    write(TAKBIR, takbir)
    for old in (RAW_DIR / "adhan_full.ogg", RAW_DIR / "adhan_takbir.ogg"):
        old.unlink(missing_ok=True)
    print(f"gain {PEAK_DBFS - 20 * np.log10(peak):+.1f} dB")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="only verify the source and the files")
    args = parser.parse_args()
    try:
        if args.check:
            check()
        else:
            build()
            check()
    except BuildError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
