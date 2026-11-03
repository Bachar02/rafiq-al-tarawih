/// Arabic text normalization: a line-for-line port of engine/src/rafiq/normalize.py.
///
/// The same function runs on the Quran index and on whatever the speech model
/// produces, folding away every distinction an ASR model (or a keyboard) is
/// likely to get wrong. It must stay identical to the Python reference:
/// test/core/normalize_golden_test.dart replays golden outputs generated from
/// Python (tools/golden/make_golden.py) and fails on any difference.
library;

// Harakat, Quranic annotation marks, superscript alef, small high/low signs.
final _diacritics = RegExp('[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿ]');

const _tatweel = 'ـ';

/// Letter folding: each key collapses into its value.
const letterMap = <String, String>{
  // alef variants -> bare alef
  'آ': 'ا', // آ
  'أ': 'ا', // أ
  'إ': 'ا', // إ
  'ٱ': 'ا', // ٱ alef wasla (Uthmani script)
  'ٲ': 'ا',
  'ٳ': 'ا',
  // hamza on a seat -> the seat
  'ؤ': 'و', // ؤ -> و
  'ئ': 'ي', // ئ -> ي
  // alef maksura -> yeh
  'ى': 'ي', // ى -> ي
  // teh marbuta -> heh
  'ة': 'ه', // ة -> ه
  // Persian / Urdu codepoints that leak in from some keyboards and models
  'ک': 'ك', // ک -> ك
  'ی': 'ي', // ی -> ي
  'ہ': 'ه', // ہ -> ه
};

/// Dropped outright: a standalone hamza is often omitted or seated by ASR.
const _dropChars = {'ء', _tatweel};

// After folding, anything that is not a basic Arabic letter is a word break.
final _nonArabic = RegExp('[^ء-ي]+');

/// Fold [text] to the canonical matching form: space-separated bare letters.
String normalize(String text) {
  final stripped = text.replaceAll(_diacritics, '');
  final out = StringBuffer();
  for (final rune in stripped.runes) {
    final ch = String.fromCharCode(rune);
    if (_dropChars.contains(ch)) continue;
    out.write(letterMap[ch] ?? ch);
  }
  return out.toString().replaceAll(_nonArabic, ' ').trim();
}

/// Normalize and split into words.
List<String> tokenize(String text) {
  final n = normalize(text);
  return n.isEmpty ? const [] : n.split(' ');
}
