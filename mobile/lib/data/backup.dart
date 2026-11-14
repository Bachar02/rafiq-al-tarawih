/// A backup: everything Rafiq keeps on the phone, in one file the user
/// keeps where they like (Downloads, Drive, a message to themselves), to
/// bring back after deleting the app or on a new phone.
///
/// Rafiq keeps all of the user's data in SharedPreferences: settings,
/// bookmarks, notes, the reading position and log, the khatm, adhkar counts,
/// prayer settings and the Taraweeh nights. A backup is all of it, value by
/// value with its type, so restoring gives back exactly what was there,
/// including records a newer store version would migrate itself.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Why a file cannot be restored.
enum BackupProblem {
  /// Not a Rafiq backup, or damaged.
  notABackup,

  /// Made by a newer Rafiq, in a form this one does not know.
  tooNew,
}

class BackupException implements Exception {
  const BackupException(this.problem, [this.detail = '']);

  final BackupProblem problem;
  final String detail;

  @override
  String toString() => 'BackupException(${problem.name}${detail.isEmpty ? '' : ': $detail'})';
}

@immutable
class Backup {
  Backup({required this.createdAt, required Map<String, Object> values}) : values = Map.unmodifiable(values);

  /// What the file says it is.
  static const format = 'rafiq-backup';
  static const version = 1;

  /// A file larger than this is not one of ours (a backup is a few hundred
  /// kilobytes at most): refused before it is read into memory.
  static const maxBytes = 20 * 1024 * 1024;

  final DateTime createdAt;

  /// Every stored value by key: `bool`, `int`, `double`, `String` or
  /// `List<String>`.
  final Map<String, Object> values;

  /// Everything in [prefs] now.
  factory Backup.capture(SharedPreferences prefs, DateTime now) => Backup(
        createdAt: now,
        values: {
          for (final key in prefs.getKeys())
            if (prefs.get(key) case final Object value) key: value is List ? List<String>.from(value) : value,
        },
      );

  /// The file's name: the day it was made, so several sort by date.
  String get fileName {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'rafiq-backup-${createdAt.year}-${two(createdAt.month)}-${two(createdAt.day)}.json';
  }

  String encode() => const JsonEncoder.withIndent(' ').convert({
        'format': format,
        'v': version,
        'created': createdAt.toUtc().toIso8601String(),
        'values': {
          for (final e in (values.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
            e.key: {'t': _typeOf(e.value), 'v': e.value},
        },
      });

  /// Reads a file made by [encode], checking all of it before anything is
  /// restored. Throws [BackupException].
  static Backup decode(String raw) {
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const BackupException(BackupProblem.notABackup, 'not JSON');
    }
    if (json is! Map || json['format'] != format) throw const BackupException(BackupProblem.notABackup);
    final v = json['v'];
    if (v is! int) throw const BackupException(BackupProblem.notABackup, 'no version');
    if (v > version) throw BackupException(BackupProblem.tooNew, 'version $v');
    final created = DateTime.tryParse('${json['created']}');
    final entries = json['values'];
    if (created == null || entries is! Map) throw const BackupException(BackupProblem.notABackup, 'no values');
    final values = <String, Object>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      if (key is! String || key.isEmpty || value is! Map) {
        throw BackupException(BackupProblem.notABackup, 'entry $key');
      }
      values[key] = _valueOf(key, value['t'], value['v']);
    }
    return Backup(createdAt: created.toLocal(), values: values);
  }

  /// Makes [prefs] hold exactly what this backup holds: what is not in it
  /// goes, the rest is written. True if every write succeeded.
  Future<bool> restoreInto(SharedPreferences prefs) async {
    var ok = true;
    for (final key in prefs.getKeys().toList()) {
      if (!values.containsKey(key)) ok &= await prefs.remove(key);
    }
    for (final MapEntry(:key, :value) in values.entries) {
      ok &= await switch (value) {
        final bool b => prefs.setBool(key, b),
        final int i => prefs.setInt(key, i),
        final double d => prefs.setDouble(key, d),
        final String s => prefs.setString(key, s),
        final List<String> l => prefs.setStringList(key, l),
        _ => Future.value(false),
      };
    }
    return ok;
  }

  static String _typeOf(Object value) => switch (value) {
        bool() => 'b',
        int() => 'i',
        double() => 'd',
        String() => 's',
        List<String>() => 'l',
        _ => throw ArgumentError.value(value, 'value', 'not a stored type'),
      };

  static Object _valueOf(String key, Object? type, Object? value) {
    final parsed = switch ((type, value)) {
      ('b', final bool b) => b,
      ('i', final int i) => i,
      // JSON writes 2.0 as 2.0, but a hand-edited file may say 2.
      ('d', final num d) => d.toDouble(),
      ('s', final String s) => s,
      ('l', final List<dynamic> l) when l.every((e) => e is String) => List<String>.from(l),
      _ => null,
    };
    if (parsed == null) throw BackupException(BackupProblem.notABackup, 'value of $key');
    return parsed;
  }
}
