# Quran data

## Sources

Both raw files come from the [Tanzil Project](https://tanzil.net) and are
licensed **Creative Commons Attribution 3.0**.

| File | What it is | Origin |
|------|-----------|--------|
| `raw/quran-simple-clean.txt` | 6236 verses, `surah\|ayah\|text`, diacritics stripped | Tanzil Quran Text, Simple Clean, v1.1 |
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

The tradeoff is that Simple Clean is not suitable for **display** — users
expect the Uthmani mushaf script. Phase 5 will add `raw/quran-uthmani.txt`
as a parallel display text, keyed by the same `(surah, ayah)`. Matching and
display stay deliberately separate: one is optimised for recall, the other for
being correct on screen.

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
  "sajdas":  [ { "index": 1, "surah": 7, "ayah": 206, "type": "recommended" }, ... ]
}
```

`id` is a global 1-based verse index (1 = 1:1, 6236 = 114:6). It exists so the
matcher can build sliding windows that cross surah boundaries without special
cases, and so the tracker can express "how far off was this prediction?" as
plain integer arithmetic.

`juzs` matter because Taraweeh is commonly one juz per night — that is a strong
prior on where the imam will be. `sajdas` matter because the UI should signal a
prostration ayah as it arrives.

The XML also carries hizb, manzil, ruku and mushaf page boundaries. Those are
not parsed yet; they belong to a mushaf reader rather than to recognition. The
raw XML is committed, so adding them later is a few lines.
