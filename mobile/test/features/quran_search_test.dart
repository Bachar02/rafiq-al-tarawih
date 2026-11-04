import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/features/search/quran_search.dart';

import '../support/fakes.dart';

void main() {
  final quran = loadQuran();
  final search = QuranSearch(quran, loadSurahNames());
  int id(int s, int a) => quran.verseId(s, a)!;
  List<int> ids(SearchResults r) => [for (final t in r.targets) t.verseId];

  test('references, in any common form and in Arabic digits', () {
    for (final q in ['2:255', '2 255', '2.255', ' 2 : 255 ', '٢:٢٥٥', '۲:۲۵۵']) {
      final r = search.search(q);
      expect(r.targets.single, isA<AyahTarget>(), reason: q);
      expect(ids(r), [id(2, 255)], reason: q);
    }
  });

  test('a reference that does not exist finds nothing', () {
    expect(search.search('2:287').isEmpty, isTrue);
    expect(search.search('115:1').isEmpty, isTrue);
  });

  test('pages and juz by name, within range', () {
    // Page 293 holds the opening of al-Kahf, but begins with the end of al-Isra.
    expect(ids(search.search('page 293')), [id(17, 105)]);
    expect(ids(search.search('p42')), [quran.pages.start(42)]);
    expect(ids(search.search('صفحة ٥٨٢')), [id(78, 1)]);
    expect(ids(search.search('juz 2')), [id(2, 142)]);
    expect(ids(search.search('جزء 30')), [id(78, 1)]);
    expect(search.search('page 605').isEmpty, isTrue);
    expect(search.search('juz 31').isEmpty, isTrue);
  });

  test('a bare number offers the surah, the juz and the page it could mean', () {
    final r = search.search('18');
    expect(r.targets.map((t) => t.runtimeType), [SurahTarget, JuzTarget, PageTarget]);
    expect(ids(r), [id(18, 1), quran.juzs.start(18), quran.pages.start(18)]);
    expect(search.search('500').targets.single, isA<PageTarget>());
  });

  test('surah names in English, the data transliteration and Arabic', () {
    expect((search.search('kahf').targets.single as SurahTarget).surah, 18);
    expect((search.search('Yaseen').targets.single as SurahTarget).surah, 36);
    expect([for (final t in search.search('الكهف').targets) (t as SurahTarget).surah], [18]);
  });

  test('Arabic text: tashkeel, hamza and alef forms do not matter', () {
    final plain = search.search('الله لا اله الا هو الحي القيوم');
    final marked = search.search('ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ');
    expect([for (final v in plain.ayahs) v.id], contains(id(2, 255)));
    expect([for (final v in marked.ayahs) v.id], [for (final v in plain.ayahs) v.id]);
    expect(plain.ayahTotal, plain.ayahs.length);
  });

  test('results are in mushaf order and capped, with the full count', () {
    final r = search.search('الله');
    expect(r.ayahTotal, greaterThan(QuranSearch.maxAyahs));
    expect(r.ayahs, hasLength(QuranSearch.maxAyahs));
    final order = [for (final v in r.ayahs) v.id];
    expect(order, [...order]..sort());
  });

  test('one Arabic letter is too little to search the text', () {
    final r = search.search('ق');
    expect(r.ayahs, isEmpty);
    expect(r.textTooShort, isTrue);
  });

  test('nothing typed, nothing found', () {
    expect(search.search('   ').isEmpty, isTrue);
    expect(search.search('zzzz').isEmpty, isTrue);
  });
}
