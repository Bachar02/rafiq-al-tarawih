# Quran data

## Sources

Both raw files come from the [Tanzil Project](https://tanzil.net) and are
licensed **Creative Commons Attribution 3.0**.

| File | What it is | Origin |
|------|-----------|--------|
| `raw/quran-simple-clean.txt` | 6236 verses, `surah\|ayah\|text`, diacritics stripped | Tanzil Quran Text, Simple Clean, v1.1 |
| `raw/quran-uthmani.txt` | 6236 verses, Uthmani script with full tashkeel (display text) | Tanzil Quran Text, Uthmani, v1.1 |
| `raw/quran-data.xml` | Surah names, ayah counts, juz/hizb/page/sajda boundaries | `tanzil.net/res/text/metadata/quran-data.xml` |

**These files are verbatim and must not be edited.** Tanzil's terms permit
copying and distribution but not modification, and require that the copyright
block stay intact. Everything derived from them lives in generated artifacts,
never by hand-patching the source. If a correction is ever needed, take it from
an updated Tanzil release rather than editing in place.

## Why "Simple Clean"

Tanzil publishes several text variants. Simple Clean has diacritics and
Quranic orthography removed, which makes it the right basis for **matching**:
ASR output will never carry correct tashkeel, so an index built on the Uthmani
script would force us to strip it anyway.

The tradeoff is that Simple Clean is not suitable for **display**: users
expect the Uthmani mushaf script. So `raw/quran-uthmani.txt` is carried in
parallel and every verse gets both `text` (Simple Clean, for matching) and
`text_uthmani` (for screens), keyed by the same `(surah, ayah)`. The build
checks that the two files line up verse for verse.

## Build

```bash
py data/build_quran.py
```

Reads the two raw files and writes `data/quran.json` (gitignored — it is
derived, and regenerating it is cheap and deterministic).

The script is strict on purpose: it cross-validates the text file against the
metadata XML, which are independent files, and **aborts on any mismatch**
rather than emitting a subtly wrong Quran. It checks that

- the text contains exactly 6236 verses and the XML exactly 114 surahs,
- the per-surah ayah counts agree between the two files,
- ayah numbers run contiguously from 1 within every surah,
- the XML's cumulative `start` offsets agree with the text's actual ordering,
- no verse text is empty.

A silent data error here would surface much later as an inexplicable accuracy
problem in the matcher, so it is worth failing loudly at build time.

## The basmala

Tanzil prefixes ayah 1 of every surah except 1 and 9 with
"بسم الله الرحمن الرحيم". In the Hafs numbering the basmala is **not** part of
those ayahs, and leaving it in would put 113 copies of the phrase in the matching
index, making every surah opening ambiguous. The build strips it (and aborts if
it is not there to strip) and records `has_basmala` on the surah instead.
Al-Fatiha keeps it as ayah 1, and 27:30 keeps it mid-verse.

The Uthmani file is split the same way, and each surah keeps its own verbatim
Uthmani basmala as `basmala_uthmani`. Tanzil prints it as بِّسْمِ, with a shadda
on the ba, in surahs 95 and 97 (as the Madinah mushaf does). Both forms are
accepted. The reference form is taken from ayah 1:1 rather than typed into the
script, because the order of its combining marks matters.

## Shape of `quran.json`

```jsonc
{
  "meta":    { "source": "...", "license": "...", "verse_count": 6236, ... },
  "surahs":  [ { "index": 93, "name_ar": "الضحى", "name_translit": "Ad-Dhuhaa",
                 "name_en": "The Morning Hours", "ayah_count": 11,
                 "revelation_type": "Meccan", "revelation_order": 11,
                 "first_verse_id": 6091, "has_basmala": true }, ... ],
  "verses":  [ { "id": 6092, "surah": 93, "ayah": 2,
                 "text": "والليل اذا سجى" }, ... ],
  "juzs":    [ { "index": 1, "surah": 1, "ayah": 1 }, ... ],
  "sajdas":  [ { "index": 1, "surah": 7, "ayah": 206, "type": "recommended" }, ... ],
  "pages":   [ { "index": 1, "surah": 1, "ayah": 1 }, ... ],          // 604
  "hizb_quarters": [ { "index": 1, "surah": 1, "ayah": 1 }, ... ]   // 240
}
```

`id` is a global 1-based verse index (1 = 1:1, 6236 = 114:6). It exists so the
matcher can build sliding windows that cross surah boundaries without special
cases, and so the tracker can express "how far off was this prediction?" as
plain integer arithmetic.

`juzs` matter because Taraweeh is commonly one juz per night — that is a strong
prior on where the imam will be. `sajdas` matter because the UI should signal a
prostration ayah as it arrives.

`pages` and `hizb_quarters` are for the reader: page starts follow the
604-page Madinah mushaf (the King Fahd Complex print), and the quarters are the
rubʿ al-ḥizb marks, 8 per juz. They are *starts only*: the app's text flows and
is not a facsimile of the printed page. The build checks that each table is a
complete, ordered partition starting at 1:1, and that every juz begins exactly
at its first hizb quarter (two independent tables in the XML). The engine
tests add hand-written anchors from the printed mushaf (juz start pages,
Ayat al-Kursi on page 42, al-Kahf on 293, …) in
`engine/tests/test_quran_divisions.py`.

The XML also carries manzil and ruku boundaries. Those are not parsed; nothing
uses them yet.

## Translations and tafsir

The app bundles four texts from [QuranEnc.com](https://quranenc.com)
(Encyclopedia of the Noble Quran). Tanzil's translations are not used: Tanzil
allows them for non-commercial use only.

| Key | Kind | Language | Text | Issued by | Version |
|-----|------|----------|------|-----------|---------|
| `english_saheeh` | translation | English | Saheeh International | Noor International Center | 1.1.2 |
| `french_hameedullah` | translation | French | Muhammad Hamidullah | Muhammad Hamidullah | 1.0.2 |
| `arabic_moyassar` | tafsir | Arabic | At-Tafsir Al-Muyassar | King Fahd Glorious Quran Printing Complex | 1.0.0 |
| `french_mokhtasar` | tafsir | French | Al-Mukhtasar fi Tafsir al-Quran | Tafsir Center for Quranic Studies | 1.0.0 |

QuranEnc has no English tafsir, so English readers are offered Al-Muyassar
in Arabic, labelled "In Arabic".

**QuranEnc's terms** (on every page of the site) allow downloading and
republishing on these conditions:

1. No modification, addition or deletion of the content.
2. The publisher and the source (QuranEnc.com) are clearly credited.
3. The version number is named when the translation is republished.
4. The transcript information is kept inside the document.
5. Notes on a translation are sent to QuranEnc.com.
6. The translation is kept at the latest version issued by QuranEnc.com.
7. No inappropriate advertisements are shown with the translations.

How the pipeline keeps them:

- `raw/quranenc/<key>.zip` is QuranEnc's own SQLite database, verbatim. Its
  SHA-256, version and update date are pinned in `texts.json`.
- `build_texts.py` copies each ayah's text and footnotes byte for byte into
  `mobile/assets/texts/<key>.json`. Only the container changes. It also
  writes `catalog.json`: names, credits, versions, URLs.
- The build checks every text against `quran-data.xml`: 6236 ayahs, surah by
  surah, in order, and none empty. Any mismatch aborts. The tests in `tests/`
  show that a damaged or swapped file is refused.
- The app shows the name, the credit, the version and "QuranEnc.com" under
  every text, and lists them all in Settings → About (conditions 2 to 4). It
  has no ads.
- Before each release, run `py data/build_texts.py updates`. If a text is
  behind, run `fetch KEY`, rebuild, and review the diff (condition 6).

```bash
py data/build_texts.py                 # build the assets from data/raw/quranenc/
py data/build_texts.py --check         # CI: fail if the assets are stale
py data/build_texts.py updates         # is any text behind QuranEnc? (exit 1 if so)
py data/build_texts.py fetch [KEY...]  # download the current version and re-pin it
```

**Adding a text:** add its entry to `texts.json` (key from QuranEnc's API,
names and credit in en/fr/ar), run `fetch KEY` and then the build. Order
within a kind is the preference order: the app shows the first text in the
interface language, else the first English translation or Arabic tafsir.
