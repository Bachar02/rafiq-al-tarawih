import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final made = DateTime(2026, 11, 4, 20, 15);

  /// One of each stored type, as the app stores them.
  const stored = <String, Object>{
    'dhikr_reminders_on': true,
    'dhikr_every_hours': 3,
    'text_scale': 1.25,
    'bookmarks.v1': '{"v":1,"items":[{"verse":262,"at":"2026-11-01T10:00:00.000Z"}]}',
    'recent_searches': ['الصبر', 'mercy'],
  };

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  Matcher problem(BackupProblem p) => throwsA(isA<BackupException>().having((e) => e.problem, 'problem', p));

  test('everything stored, with its type, through a file and back', () async {
    final backup = Backup.capture(await prefsWith(stored), made);
    final again = Backup.decode(backup.encode());
    expect(again.values, stored);
    expect(again.values['text_scale'], isA<double>());
    expect(again.values['dhikr_every_hours'], isA<int>());
    expect(again.values['recent_searches'], isA<List<String>>());
    expect(again.createdAt, made);
    expect(backup.fileName, 'rafiq-backup-2026-11-04.json');
  });

  test('the file says what it is, and what made it', () async {
    final json = jsonDecode(Backup.capture(await prefsWith(stored), made).encode()) as Map<String, dynamic>;
    expect(json['format'], 'rafiq-backup');
    expect(json['v'], 1);
    expect((json['values'] as Map)['dhikr_every_hours'], {'t': 'i', 'v': 3});
  });

  test('restored: exactly what the backup holds, nothing of what was there', () async {
    final backup = Backup.decode(Backup.capture(await prefsWith(stored), made).encode());
    final phone = await prefsWith({'dhikr_reminders_on': false, 'notes.v1': '{"v":1,"items":[]}'});
    expect(await backup.restoreInto(phone), isTrue);
    expect({for (final k in phone.getKeys()) k: phone.get(k)}, stored);
    expect(phone.getStringList('recent_searches'), ['الصبر', 'mercy']);
  });

  test('a file that is not a backup is refused before anything is touched', () {
    expect(() => Backup.decode('not json'), problem(BackupProblem.notABackup));
    expect(() => Backup.decode('[]'), problem(BackupProblem.notABackup));
    expect(() => Backup.decode('{"format":"other","v":1}'), problem(BackupProblem.notABackup));
    expect(() => Backup.decode('{"format":"rafiq-backup","v":1,"created":"x","values":{}}'),
        problem(BackupProblem.notABackup));
  });

  test('a value of the wrong type spoils the file', () {
    String file(Map<String, Object?> entry) => jsonEncode({
          'format': 'rafiq-backup',
          'v': 1,
          'created': made.toUtc().toIso8601String(),
          'values': {'k': entry},
        });
    expect(Backup.decode(file({'t': 'd', 'v': 2})).values['k'], 2.0, reason: 'a whole number is still a double');
    expect(() => Backup.decode(file({'t': 'i', 'v': 'three'})), problem(BackupProblem.notABackup));
    expect(
        () => Backup.decode(file({
              't': 'l',
              'v': [1, 2]
            })),
        problem(BackupProblem.notABackup));
    expect(() => Backup.decode(file({'t': 'x', 'v': true})), problem(BackupProblem.notABackup));
  });

  test('a backup from a newer Rafiq is said to be so', () {
    expect(
      () => Backup.decode('{"format":"rafiq-backup","v":2,"created":"2027-01-01T00:00:00Z","values":{}}'),
      problem(BackupProblem.tooNew),
    );
  });
}
