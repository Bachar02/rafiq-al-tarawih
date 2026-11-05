import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/core/text/quran_display.dart';

import '../support/fakes.dart';

void main() {
  test('ayah-end marker: ۝ and Arabic-Indic digits, in every language', () {
    expect(ayahEndMarker(3), '۝٣');
    expect(ayahEndMarker(286), '۝٢٨٦');
    expect(arabicDigits(1029), '١٠٢٩');
  });

  test('the text is joined to its marker by a no-break space', () {
    expect(displayAyahText('مَا وَدَّعَكَ رَبُّكَ وَمَا قَلَىٰ'), 'مَا وَدَّعَكَ رَبُّكَ وَمَا قَلَىٰ$nbsp');
  });

  test('the space before a standalone pause mark becomes unbreakable', () {
    // 2:2 — ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى
    const text = 'لَا رَيْبَ ۛ فِيهِ ۛ هُدًى';
    expect(preparePauseMarks(text), 'لَا رَيْبَ$nbspۛ فِيهِ$nbspۛ هُدًى');
  });

  test('whole Quran: only line breaks change, never the text', () {
    final quran = loadQuran();
    var pauseMarks = 0;
    for (final v in quran.verses) {
      final shown = displayAyahText(v.uthmani);
      // Same letters, marks and order: only spaces became no-break spaces.
      expect(shown.replaceAll(nbsp, ' ').trimRight(), v.uthmani, reason: 'verse ${v.id}');
      // No line can start with a pause mark: none follows an ordinary space.
      expect(RegExp(' [ۖ-ۜ]').hasMatch(shown), isFalse, reason: 'verse ${v.id}');
      pauseMarks += nbsp.allMatches(shown).length - 1;
    }
    expect(pauseMarks, greaterThan(4000)); // ~4,400 standalone pause marks in the Hafs text
  });

  test('justify only when the column is wide enough for the font size', () {
    expect(justifyQuran(columnWidth: 300, fontSize: 26), isTrue); // 11.54
    expect(justifyQuran(columnWidth: 272, fontSize: 26), isFalse); // 320px phone
    expect(justifyQuran(columnWidth: 342, fontSize: 26 * 1.3), isFalse); // large text
  });
}
