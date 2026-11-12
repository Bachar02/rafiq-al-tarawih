"""Fetch the quran-align word timings used to score word tracking exactly (PLAN.md §31).

Source: Collin Fair, quran-align, release 2016-11-24, https://github.com/cpfair/quran-align
Licence: Creative Commons Attribution 4.0 International (CC BY 4.0), the data files.

One archive (5,807,871 bytes) holds 12 recitations. Only those our recordings
use are kept; the archive is then deleted. Everything lands in
eval/data/quran-align/, which git ignores: the data is not redistributed.

    py eval/fetch_quran_align.py                 # download, verify, keep what is needed
    py eval/fetch_quran_align.py --zip FILE      # the same, from an archive already downloaded

The archive's SHA-256 was recorded at the first download (GitHub publishes no
digest for assets this old; the size matched the release API). Each kept file
is also checked against the SHA-1 the archive's own README lists.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

URL = (
    "https://github.com/cpfair/quran-align/releases/download/"
    "release-2016-11-24/quran-align-data-2016-11-24.zip"
)
VERSION = "release-2016-11-24"
SIZE = 5_807_871
SHA256 = "5eeb045d8a7895208c94d2d7ec243567f8f550728835411527c4ffa1e789c9b7"

# Recitations our recordings use, exactly or at another bitrate (to be verified
# against our audio before use), with the SHA-1 the archive's README gives.
KEEP = {
    "Alafasy_128kbps.json": "167bfc53255152aaf8c9a2e5e79c1160134c77a4",
    "Abdurrahmaan_As-Sudais_192kbps.json": "4315194bc88db14192201426fb4f6617bffac4ac",
    "Minshawy_Murattal_128kbps.json": "2a24d42e7f3a018c56600fc4ddd580f214b20a39",
    "Saood_ash-Shuraym_128kbps.json": "59fd80d144caa6fe79a917a8d1dddf18087b3bcc",
    "Husary_64kbps.json": "8e7a24f66f98f176dfddf65b434643a6655c694d",
    "Abdul_Basit_Murattal_64kbps.json": "029e32d2cdc869e2f33ae86fd21214952d18f33d",
}
NOTICES = ["README", "LICENSE"]  # the attribution and licence travel with the data

OUT = Path(__file__).resolve().parent / "data" / "quran-align"

ATTRIBUTION = f"""Word timings: quran-align by Collin Fair, {VERSION}
{URL}
Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0),
https://creativecommons.org/licenses/by/4.0/
Archive SHA-256 {SHA256}, {SIZE} bytes. Kept: {", ".join(KEEP)} (unchanged).
Used only to evaluate Rafiq's word tracking; not redistributed.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip", type=Path, default=None, help="an archive already downloaded")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=OUT) as tmp:
        archive = args.zip
        if archive is None:
            archive = Path(tmp) / "archive.zip"
            print(f"downloading {URL}")
            urllib.request.urlretrieve(URL, archive)
        data = archive.read_bytes()
        if len(data) != SIZE or hashlib.sha256(data).hexdigest() != SHA256:
            print(f"{archive}: size or SHA-256 does not match {VERSION}; nothing kept", file=sys.stderr)
            return 1
        with zipfile.ZipFile(archive) as z:
            names = set(z.namelist())
            for name in [*KEEP, *NOTICES]:
                if name not in names:
                    print(f"{name} missing from the archive", file=sys.stderr)
                    return 1
                body = z.read(name)  # by exact name: nothing else is extracted
                if name in KEEP and hashlib.sha1(body).hexdigest() != KEEP[name]:
                    print(f"{name}: SHA-1 does not match the archive's README", file=sys.stderr)
                    return 1
                (OUT / name).write_bytes(body)
    (OUT / "SOURCE.txt").write_bytes(ATTRIBUTION.encode("utf-8"))
    print(f"kept {len(KEEP)} recitations in {OUT} (archive verified, then discarded)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
