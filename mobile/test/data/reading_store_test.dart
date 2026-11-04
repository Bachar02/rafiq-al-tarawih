import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<(PrefsReadingStore, SharedPreferences)> store([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return (PrefsReadingStore(prefs), prefs);
  }

  final at = DateTime.utc(2026, 11, 4, 18);

  test('nothing saved yet', () async {
    final (s, _) = await store();
    expect(s.readingPosition(), isNull);
    expect(s.taraweehPosition(), isNull);
    expect(s.bookmarks(), isEmpty);
  });

  test('positions round-trip, and the two never mix', () async {
    final (s, prefs) = await store();
    expect(await s.saveReadingPosition(SavedPosition(verseId: 262, savedAt: at)), isTrue);
    expect(await s.saveTaraweehPosition(SavedPosition(verseId: 700, savedAt: at)), isTrue);
    final again = PrefsReadingStore(prefs); // a restart
    expect(again.readingPosition()?.verseId, 262);
    expect(again.readingPosition()?.savedAt.toUtc(), at);
    expect(again.taraweehPosition()?.verseId, 700);
  });

  test('bookmarks round-trip newest first, one per ayah', () async {
    final (s, prefs) = await store();
    await s.saveBookmarks([
      Bookmark(verseId: 10, createdAt: at),
      Bookmark(verseId: 20, createdAt: at.add(const Duration(days: 1))),
    ]);
    expect([for (final b in PrefsReadingStore(prefs).bookmarks()) b.verseId], [20, 10]);
  });

  test('an unreadable position is kept aside, never overwritten', () async {
    final (s, prefs) = await store({PrefsReadingStore.readingKey: '{not json'});
    expect(s.readingPosition(), isNull);
    // The next save goes through only once the original is safe.
    expect(await s.saveReadingPosition(SavedPosition(verseId: 5, savedAt: at)), isTrue);
    final kept =
        prefs.getKeys().where((k) => k.startsWith(PrefsReadingStore.unreadablePrefix(PrefsReadingStore.readingKey)));
    expect(kept, hasLength(1));
    expect(prefs.getString(kept.single), '{not json');
    expect(s.readingPosition()?.verseId, 5);
  });

  test('a position out of range or from an unknown version is not trusted', () async {
    for (final raw in [
      '{"v":1,"verse":9999,"at":"2026-11-04T18:00:00Z"}',
      '{"v":2,"verse":5,"at":"2026-11-04T18:00:00Z"}',
      '{"v":1,"verse":"5","at":"2026-11-04T18:00:00Z"}',
    ]) {
      final (s, prefs) = await store({PrefsReadingStore.taraweehKey: raw});
      expect(s.taraweehPosition(), isNull, reason: raw);
      await s.saveTaraweehPosition(SavedPosition(verseId: 6, savedAt: at));
      final kept = prefs.getKeys().where((k) => k.contains('.unreadable.')).map(prefs.getString);
      expect(kept, [raw], reason: 'the unknown record is kept as it was');
    }
  });

  test('readable bookmarks survive a damaged one, and the original is kept', () async {
    const raw = '{"v":1,"items":[{"verse":10,"at":"2026-11-04T18:00:00Z"},{"verse":-1,"at":"x"},'
        '{"verse":20,"at":"2026-11-05T18:00:00Z"},{"verse":10,"at":"2026-11-03T18:00:00Z"}]}';
    final (s, prefs) = await store({PrefsReadingStore.bookmarksKey: raw});
    expect([for (final b in s.bookmarks()) b.verseId], [20, 10]);
    await s.saveBookmarks(s.bookmarks());
    final kept = prefs.getKeys().where((k) => k.contains('.unreadable.')).map(prefs.getString);
    expect(kept, [raw]);
  });

  test('a bookmarks record of the wrong shape is kept and reads as empty', () async {
    final (s, prefs) = await store({PrefsReadingStore.bookmarksKey: '[1,2,3]'});
    expect(s.bookmarks(), isEmpty);
    await s.saveBookmarks([Bookmark(verseId: 1, createdAt: at)]);
    expect(prefs.getKeys().where((k) => k.contains('.unreadable.')).map(prefs.getString), ['[1,2,3]']);
  });
}
