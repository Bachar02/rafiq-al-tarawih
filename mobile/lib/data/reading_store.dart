/// Where the user is: the personal reading position, where Taraweeh last
/// ended, and bookmarks. Kept apart from [AppSettings]: these are the user's
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

import 'quran.dart';

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

  SavedPosition? taraweehPosition();
  Future<bool> saveTaraweehPosition(SavedPosition position);

  /// Newest first.
  List<Bookmark> bookmarks();
  Future<bool> saveBookmarks(List<Bookmark> bookmarks);

  /// Pages read on each day (local `yyyy-mm-dd`).
  ReadingLog readingLog();
  Future<bool> saveReadingLog(ReadingLog log);
}

/// The pages read on each day, for the daily goal. Immutable.
@immutable
class ReadingLog {
  const ReadingLog([this.days = const {}]);

  /// Days older than this are dropped when saving.
  static const keepDays = 90;

  final Map<String, Set<int>> days;

  static String dayKey(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';

  Set<int> on(DateTime local) => days[dayKey(local)] ?? const {};

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
  static const bookmarksKey = 'bookmarks.v1';
  static const logKey = 'reading_log.v1';

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
  Future<bool> saveTaraweehPosition(SavedPosition position) => _write(taraweehKey, position.toJson());

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
