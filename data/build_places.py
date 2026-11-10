"""Bundle the list of towns the prayer times can be set for.

The app never sends a position anywhere. To name where the phone is, and to
let someone choose a town by hand, it carries its own list: every populated
place of 5,000 people or more from GeoNames (CC BY 4.0), with its English,
French and Arabic names, its country and its coordinates.

Sources (https://download.geonames.org/export/dump/, see its readme.txt):
    cities5000.zip        the towns: name, coordinates, country, population
    alternateNamesV2.zip  their names by language (fr, ar), and the countries'
    countryInfo.txt       the countries: ISO code, English name, geonameid

The dumps are large and change daily, so they are not kept in the repository:
`fetch` downloads them into data/raw/geonames/ (gitignored), and the build
writes two small tab-separated files into mobile/assets/places/:

    cities.tsv     name, French name, Arabic name, country code, latitude, longitude
                   (most populous first; a French or Arabic name is empty when
                   GeoNames has none, or when it is the same as the name)
    countries.tsv  country code, English name, French name, Arabic name

Usage:
    py data/build_places.py fetch   # download the three dumps (about 215 MB)
    py data/build_places.py         # build mobile/assets/places/ from them
"""

from __future__ import annotations

import argparse
import io
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent
ROOT = DATA_DIR.parent
RAW_DIR = DATA_DIR / "raw" / "geonames"
ASSET_DIR = ROOT / "mobile" / "assets" / "places"

DUMP = "https://download.geonames.org/export/dump/"
FILES = ("cities5000.zip", "alternateNamesV2.zip", "countryInfo.txt")
USER_AGENT = "rafiq-build (Quran reader; bundles a list of towns for offline prayer times)"

LANGUAGES = ("fr", "ar")

# Populated places that are towns in their own right. Left out: sections of
# a town (PPLX: a search for "Tunis" should not list its districts), and
# places abandoned, destroyed or historical (PPLQ, PPLW, PPLH).
EXCLUDED_FEATURES = {"PPLX", "PPLQ", "PPLW", "PPLH", "PPLCH"}
NUMBERED_DISTRICT = re.compile(r"^(.+?) \d{1,2}(?:\s.*)?$")

# Where the list departs from GeoNames, each on purpose:
#
# Jerusalem (geonameid 281184). GeoNames files the city under IL, and its
# eastern part (the Old City, al-Aqsa) under PS as a section of it, which the
# list leaves out like every section. The list keeps the one entry for the
# city, and places it in Palestine, as the people this app is made for know
# it. This is an editorial choice of the app, not GeoNames'.
COUNTRY_OF = {281184: "PS"}

# GeoNames' English name for PS is "Palestinian Territory"; its French and
# Arabic names already say Palestine.
ENGLISH_COUNTRY_NAMES = {"PS": "Palestine"}

# Marks that steer text direction or join letters: invisible, and they would
# keep a search from matching ("أريانة" is stored with one).
INVISIBLE = dict.fromkeys(
    [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF, *range(0x202A, 0x202F), *range(0x2066, 0x206A)]
)

# Sanity floor: a truncated download must not ship as a short list.
MIN_CITIES = 40_000
MIN_COUNTRIES = 240


class BuildError(Exception):
    """A source inconsistency. Always fatal."""


def clean(name: str) -> str:
    """[name] without invisible marks, control characters or outer spaces."""
    return "".join(ch for ch in name.translate(INVISIBLE) if ch >= " ").strip()


def fetch() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        target = RAW_DIR / name
        print(f"fetching {name} ...", flush=True)
        request = urllib.request.Request(DUMP + name, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request) as response, target.open("wb") as out:
            while chunk := response.read(1 << 20):
                out.write(chunk)
        print(f"  {target.stat().st_size:,} bytes")


def _lines(zip_name: str, member: str):
    path = RAW_DIR / zip_name
    if not path.exists():
        raise BuildError(f"{path} is missing: run `py data/build_places.py fetch` first")
    with zipfile.ZipFile(path) as archive, archive.open(member) as raw:
        for line in io.TextIOWrapper(raw, encoding="utf-8", newline="\n"):
            yield line.rstrip("\n").split("\t")


def read_countries() -> dict[str, tuple[int, str]]:
    """ISO code -> (geonameid, English name)."""
    path = RAW_DIR / "countryInfo.txt"
    if not path.exists():
        raise BuildError(f"{path} is missing: run `py data/build_places.py fetch` first")
    countries: dict[str, tuple[int, str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        code, name, geonameid = fields[0], fields[4], fields[16]
        if len(code) == 2 and name and geonameid.isdigit():
            countries[code] = (int(geonameid), ENGLISH_COUNTRY_NAMES.get(code, name))
    if len(countries) < MIN_COUNTRIES:
        raise BuildError(f"only {len(countries)} countries in countryInfo.txt")
    return countries


def read_cities(countries: dict[str, tuple[int, str]]) -> list[dict]:
    cities = []
    for f in _lines("cities5000.zip", "cities5000.txt"):
        # geonameid, name, asciiname, alternatenames, latitude, longitude, feature class,
        # feature code, country code, cc2, admin1..4, population, elevation, dem, timezone, date
        country = COUNTRY_OF.get(int(f[0]), f[8])
        if f[6] != "P" or f[7] in EXCLUDED_FEATURES or country not in countries:
            continue
        name = clean(f[1])
        latitude, longitude = float(f[4]), float(f[5])
        if not name or "\t" in name or not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            raise BuildError(f"bad town: {f[:9]}")
        cities.append(
            {
                "id": int(f[0]),
                "name": name,
                "cc": country,
                "lat": latitude,
                "lon": longitude,
                "population": int(f[14] or 0),
            }
        )
    # Numbered districts filed as towns ("Paris 15 Vaugirard", "Marseille 13")
    # go too, when the town they number is in the list.
    listed = {(c["name"], c["cc"]) for c in cities}
    cities = [
        c
        for c in cities
        if not ((m := NUMBERED_DISTRICT.match(c["name"])) and (m.group(1), c["cc"]) in listed)
    ]
    if len(cities) < MIN_CITIES:
        raise BuildError(f"only {len(cities)} towns in cities5000.zip")
    # Most populous first: a search lists the great cities before their namesakes.
    cities.sort(key=lambda c: (-c["population"], c["id"]))
    return cities


def read_names(wanted: set[int]) -> dict[int, dict[str, str]]:
    """geonameid -> {language: name}, for the ids in [wanted].

    GeoNames' own choice comes first: a preferred name, then a short one (a
    country is "Tunisie", not "République tunisienne"), then the first listed.
    Historic and colloquial names are never used.
    """
    best: dict[tuple[int, str], tuple[tuple[int, int], str]] = {}
    for f in _lines("alternateNamesV2.zip", "alternateNamesV2.txt"):
        # alternateNameId, geonameid, isolanguage, name,
        # isPreferred, isShort, isColloquial, isHistoric, from, to
        language = f[2]
        if language not in LANGUAGES:
            continue
        geonameid = int(f[1])
        if geonameid not in wanted:
            continue
        flags = f[4:8] + [""] * 4
        if flags[2] == "1" or flags[3] == "1":
            continue
        name = clean(f[3])
        if not name:
            continue
        rank = (-int(flags[0] == "1"), -int(flags[1] == "1"))
        key = (geonameid, language)
        if key not in best or rank < best[key][0]:
            best[key] = (rank, name)
    names: dict[int, dict[str, str]] = {}
    for (geonameid, language), (_, name) in best.items():
        names.setdefault(geonameid, {})[language] = name
    return names


def build() -> None:
    countries = read_countries()
    cities = read_cities(countries)
    wanted = {c["id"] for c in cities} | {geonameid for geonameid, _ in countries.values()}
    print(f"{len(cities):,} towns, {len(countries)} countries; reading their names ...", flush=True)
    names = read_names(wanted)

    city_rows = []
    for c in cities:
        other = names.get(c["id"], {})
        fr, ar = (other.get(lang, "") for lang in LANGUAGES)
        # Three decimals: about a hundred metres, far finer than a prayer time needs.
        fields = [c["name"], "" if fr == c["name"] else fr, ar, c["cc"], f"{c['lat']:.3f}", f"{c['lon']:.3f}"]
        city_rows.append("\t".join(fields))
    country_rows = []
    for code in sorted(countries):
        geonameid, english = countries[code]
        other = names.get(geonameid, {})
        country_rows.append("\t".join([code, english, other.get("fr", ""), other.get("ar", "")]))

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    # Bytes, not text: the files are the same on every system (no CRLF).
    (ASSET_DIR / "cities.tsv").write_bytes(("\n".join(city_rows) + "\n").encode("utf-8"))
    (ASSET_DIR / "countries.tsv").write_bytes(("\n".join(country_rows) + "\n").encode("utf-8"))
    with_ar = sum(1 for row in city_rows if row.split("\t")[2])
    with_fr = sum(1 for row in city_rows if row.split("\t")[1])
    size = (ASSET_DIR / "cities.tsv").stat().st_size
    print(f"cities.tsv: {len(city_rows):,} towns, {size:,} bytes")
    print(f"  {with_ar:,} with an Arabic name, {with_fr:,} with a French one")
    print(f"countries.tsv: {len(country_rows)} countries")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", nargs="?", choices=["build", "fetch"], default="build")
    args = parser.parse_args()
    try:
        fetch() if args.command == "fetch" else build()
    except BuildError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
