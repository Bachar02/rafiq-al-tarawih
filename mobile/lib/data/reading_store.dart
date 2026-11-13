/// Where the user is: the personal reading position, where Taraweeh last
/// ended, bookmarks, notes, the reading log and the khatm plan. Kept apart from [AppSettings]: these are the user's
/// data, not preferences, and must never be lost.
///
/// Stored in shared preferences as small versioned JSON records keyed by
/// verse id (1..6236, the stable global index of the Hafs text). Rules:
/// - **A record that cannot be read is never overwritten.** It is copied
///   aside under a `.unreadable` key first, so a future version (or a bug
///   report) can still recover it.
/// - **A failed write is reported, not thrown**, so the caller can tell the
///   user (a bookmark) or simply try again later (a scroll position).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'khatm.dart';
import 'note.dart';
import 'quran.dart';
import 'taraweeh_ledger.dart';

/// A saved place in the Quran.
@immutable
class SavedPosition {
  const SavedPosition({required this.verseId, required this.savedAt});

  final int verseId;
  final DateTime savedAt;

  Map<String, Object> toJson() => {'v': 1, 'verse': verseId, 'at': savedAt.toUtc().toIso8601String()};

  static SavedPosition? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    final verse = json['verse'], at = DateTime.tryParse('${json['at']}');
    if (verse is! int || !_validVerse(verse) || at == null) return null;
    return SavedPosition(verseId: verse, savedAt: at.toLocal());
  }

  @override
  bool operator ==(Object other) => other is SavedPosition && other.verseId == verseId && other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(verseId, savedAt);
}

/// A bookmarked ayah.
@immutable
class Bookmark {
  const Bookmark({required this.verseId, required this.createdAt});

  final int verseId;
  final DateTime createdAt;

  Map<String, Object> toJson() => {'verse': verseId, 'at': createdAt.toUtc().toIso8601String()};

  static Bookmark? fromJson(Object? json) {
    if (json is! Map) return null;
    final verse = json['verse'], at = DateTime.tryParse('${json['at']}');
    if (verse is! int || !_validVerse(verse) || at == null) return null;
    return Bookmark(verseId: verse, createdAt: at.toLocal());
  }

  @override
  bool operator ==(Object other) => other is Bookmark && other.verseId == verseId && other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(verseId, createdAt);
}

bool _validVerse(int id) => id >= 1 && id <= Quran.verseCount;

/// Persistence for [SavedPosition]s and [Bookmark]s. An interface, so tests
/// (and a later SQLite store, if notes ever need one) can stand in.
abstract interface class ReadingStore {
  SavedPosition? readingPosition();
  Future<bool> saveReadingPosition(SavedPosition position);

  /// The single Taraweeh position of earlier versions (read once, to carry
  /// it over; never written again, never deleted).
  SavedPosition? taraweehPosition();

  /// Taraweeh night by night ([TaraweehLedger]); null if none was saved yet.
  TaraweehLedger? taraweehLedger();
  Future<bool> saveTaraweehLedger(TaraweehLedger ledger);

  /// Newest first.
  List<Bookmark> bookmarks();
  Future<bool> saveBookmarks(List<Bookmark> bookmarks);

  /// Pages read on each day (local `yyyy-mm-dd`), as the user confirmed them.
  ReadingLog readingLog();
  Future<bool> saveReadingLog(ReadingLog log);

  /// Pages that stayed on screen long enough to be read, waiting for the
  /// user to confirm them, by the day they were read.
  ReadingLog pendingReading();
  Future<bool> savePendingReading(ReadingLog pending);

  /// The active khatm plan and the finished ones.
  KhatmBook khatm();
  Future<bool> saveKhatm(KhatmBook book);

  /// Newest edit first, one per ayah.
  List<Note> notes();
  Future<bool> saveNotes(List<Note> notes);
}

/// Pages by day: the confirmed reading log (the daily goal), or the pages
/// waiting for review. Immutable.
@immutable
class ReadingLog {
  const ReadingLog([this.days = const {}]);

  /// Days older than this are dropped when saving: a year and a little
  /// more, for a year of reading history.
  static const keepDays = 400;

  final Map<String, Set<int>> days;

  static String dayKey(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';

  Set<int> on(DateTime local) => days[dayKey(local)] ?? const {};

  bool get isEmpty => days.values.every((p) => p.isEmpty);

  /// How many (day, page) entries there are.
  int get length => days.values.fold(0, (n, p) => n + p.length);

  /// This log with each of [other]'s pages added to its own day.
  ReadingLog merging(ReadingLog other) {
    var out = this;
    for (final e in other.days.entries) {
      final day = parseDay(e.key);
      if (day != null && e.value.isNotEmpty) out = out.adding(day, e.value);
    }
    return out;
  }

  /// This log without [other]'s (day, page) entries; empty days dropped.
  ReadingLog removing(ReadingLog other) => ReadingLog({
        for (final e in days.entries)
          if (e.value.difference(other.days[e.key] ?? const {}).isNotEmpty)
            e.key: e.value.difference(other.days[e.key] ?? const {}),
      });

  /// The local day a [dayKey] names.
  static DateTime? parseDay(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]), m = int.tryParse(parts[1]), d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    final day = DateTime(y, m, d);
    return dayKey(day) == key ? day : null;
  }

  /// This log with [pages] added to [local]'s day, and days older than
  /// [keepDays] before it dropped.
  ReadingLog adding(DateTime local, Iterable<int> pages) {
    final cutoff = dayKey(local.subtract(const Duration(days: keepDays)));
    final key = dayKey(local);
    return ReadingLog({
      for (final e in days.entries)
        if (e.key.compareTo(cutoff) > 0 && e.key != key) e.key: e.value,
      key: {...on(local), ...pages},
    });
  }

  Map<String, Object> toJson() => {
        'v': 1,
        'days': {
          for (final e in days.entries) e.key: ([...e.value]..sort()),
        },
      };

  static ReadingLog? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1 || json['days'] is! Map) return null;
    final days = <String, Set<int>>{};
    for (final e in (json['days'] as Map).entries) {
      final pages = e.value;
      if (e.key is! String || pages is! List) return null;
      days[e.key as String] = {
        for (final p in pages)
          if (p is int && p >= 1 && p <= 604) p
      };
    }
    return ReadingLog(days);
  }
}

class PrefsReadingStore implements ReadingStore {
  PrefsReadingStore(this._prefs);

  final SharedPreferences _prefs;

  static const readingKey = 'reading_position.v1';
  static const taraweehKey = 'taraweeh_position.v1';
  static const taraweehLedgerKey = 'taraweeh_progress.v1';
  static const bookmarksKey = 'bookmarks.v1';
  static const logKey = 'reading_log.v1';
  static const khatmKey = 'khatm.v1';
  static const notesKey = 'notes.v1';
  static const pendingKey = 'reading_pending.v1';

  /// The prefix of the keys an unreadable record is copied to, untouched
  /// (one per occurrence, suffixed with the time it was found).
  static String unreadablePrefix(String key) => '$key.unreadable.';

  /// Copies in progress. A key is not written until its copy is safe.
  final _backups = <String, Future<bool>>{};

  @override
  SavedPosition? readingPosition() => _readPosition(readingKey);

  @override
  Future<bool> saveReadingPosition(SavedPosition position) => _write(readingKey, position.toJson());

  @override
  SavedPosition? taraweehPosition() => _readPosition(taraweehKey);

  @override
  TaraweehLedger? taraweehLedger() {
    final json = _readJson(taraweehLedgerKey);
    if (json == null) return null;
    var dropped = false;
    final ledger = TaraweehLedger.fromJson(json, dropped: () => dropped = true);
    // Unreadable, whole or in part: the original is kept before any write.
    if (ledger == null || dropped) _setAside(taraweehLedgerKey);
    return ledger;
  }

  @override
  Future<bool> saveTaraweehLedger(TaraweehLedger ledger) => _write(taraweehLedgerKey, ledger.toJson());

  @override
  List<Bookmark> bookmarks() {
    final json = _readJson(bookmarksKey);
    if (json == null) return const [];
    final list = json is Map && json['v'] == 1 ? json['items'] : null;
    if (list is! List) {
      _setAside(bookmarksKey);
      return const [];
    }
    final out = <Bookmark>[];
    var dropped = 0;
    final seen = <int>{};
    for (final item in list) {
      final b = Bookmark.fromJson(item);
      if (b == null) {
        dropped++;
      } else if (seen.add(b.verseId)) {
        out.add(b);
      }
    }
    // Some entries were unreadable: keep the original whole before the next
    // save writes only the readable ones.
    if (dropped > 0) _setAside(bookmarksKey);
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(out);
  }

  @override
  Future<bool> saveBookmarks(List<Bookmark> bookmarks) => _write(bookmarksKey, {
        'v': 1,
        'items': [for (final b in bookmarks) b.toJson()]
      });

  @override
  ReadingLog readingLog() {
    final json = _readJson(logKey);
    if (json == null) return const ReadingLog();
    final log = ReadingLog.fromJson(json);
    if (log == null) _setAside(logKey);
    return log ?? const ReadingLog();
  }

  @override
  Future<bool> saveReadingLog(ReadingLog log) => _write(logKey, log.toJson());

  @override
  ReadingLog pendingReading() {
    final json = _readJson(pendingKey);
    if (json == null) return const ReadingLog();
    final log = ReadingLog.fromJson(json);
    if (log == null) _setAside(pendingKey);
    return log ?? const ReadingLog();
  }

  @override
  Future<bool> savePendingReading(ReadingLog pending) => _write(pendingKey, pending.toJson());

  @override
  KhatmBook khatm() {
    final json = _readJson(khatmKey);
    if (json == null) return KhatmBook.empty;
    var dropped = false;
    final book = KhatmBook.fromJson(json, onDropped: () => dropped = true);
    // Unreadable, whole or in part: keep the original before a save rewrites it.
    if (book == null || dropped) _setAside(khatmKey);
    return book ?? KhatmBook.empty;
  }

  @override
  Future<bool> saveKhatm(KhatmBook book) => _write(khatmKey, book.toJson());

  @override
  List<Note> notes() {
    final json = _readJson(notesKey);
    if (json == null) return const [];
    final list = json is Map && json['v'] == 1 ? json['items'] : null;
    if (list is! List) {
      _setAside(notesKey);
      return const [];
    }
    final byVerse = <int, Note>{};
    var dropped = false;
    for (final item in list) {
      final n = Note.fromJson(item);
      if (n == null) {
        dropped = true;
        continue;
      }
      final other = byVerse[n.verseId];
      // Two notes on one ayah: keep the newer, and the original record.
      if (other != null) dropped = true;
      if (other == null || n.updatedAt.isAfter(other.updatedAt)) byVerse[n.verseId] = n;
    }
    if (dropped) _setAside(notesKey);
    return List.unmodifiable(byVerse.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));
  }

  @override
  Future<bool> saveNotes(List<Note> notes) => _write(notesKey, {
        'v': 1,
        'items': [for (final n in notes) n.toJson()]
      });

  SavedPosition? _readPosition(String key) {
    final json = _readJson(key);
    if (json == null) return null;
    final position = SavedPosition.fromJson(json);
    if (position == null) _setAside(key);
    return position;
  }

  /// The decoded record, or null if there is none or it is not JSON (then set aside).
  Object? _readJson(String key) {
    final Object? raw;
    try {
      raw = _prefs.get(key);
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    if (raw is! String) {
      _setAside(key);
      return null;
    }
    try {
      return jsonDecode(raw);
    } on FormatException {
      _setAside(key);
      return null;
    }
  }

  /// Copy an unreadable record aside, so the next write cannot lose it.
  void _setAside(String key) {
    if (_backups.containsKey(key)) return;
    final raw = _prefs.get(key);
    if (raw == null) return;
    final backup = '${unreadablePrefix(key)}${DateTime.now().microsecondsSinceEpoch}';
    debugPrint('ReadingStore: $key is unreadable; kept as $backup');
    _backups[key] = _prefs.setString(backup, raw is String ? raw : '$raw').catchError((_) => false);
  }

  Future<bool> _write(String key, Object json) async {
    // Until an unreadable record is safely copied, it is not overwritten.
    final backup = _backups[key];
    if (backup != null && !await backup) return false;
    try {
      return await _prefs.setString(key, jsonEncode(json));
    } catch (_) {
      return false;
    }
  }
}
