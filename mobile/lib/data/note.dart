import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'quran.dart';

/// The user's own note on an ayah. One per ayah.
@immutable
class Note {
  const Note({required this.verseId, required this.text, required this.createdAt, required this.updatedAt});

  /// Longest note, in characters as the user sees them.
  static const maxLength = 2000;

  final int verseId;
  final String text;
  final DateTime createdAt, updatedAt;

  /// [text] as it is kept: trimmed, at most [maxLength] characters. Empty
  /// means "no note".
  static String clean(String text) {
    final trimmed = text.trim();
    final chars = trimmed.characters;
    return chars.length <= maxLength ? trimmed : chars.take(maxLength).toString().trimRight();
  }

  Map<String, Object> toJson() => {
        'verse': verseId,
        'text': text,
        'at': createdAt.toUtc().toIso8601String(),
        'edited': updatedAt.toUtc().toIso8601String(),
      };

  /// Null if unreadable. A note longer than [maxLength] (written by a later
  /// version, say) is still read: the user's words are never cut on load.
  static Note? fromJson(Object? json) {
    if (json is! Map) return null;
    final verse = json['verse'], text = json['text'];
    final at = DateTime.tryParse('${json['at']}'), edited = DateTime.tryParse('${json['edited']}');
    if (verse is! int || verse < 1 || verse > Quran.verseCount) return null;
    if (text is! String || text.trim().isEmpty || at == null || edited == null) return null;
    return Note(verseId: verse, text: text, createdAt: at.toLocal(), updatedAt: edited.toLocal());
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.verseId == verseId &&
      other.text == text &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(verseId, text, createdAt, updatedAt);
}
