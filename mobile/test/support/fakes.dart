/// Test doubles for the app's seams (see docs/DESIGN.md §4.2).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/core/audio/audio_source.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/core/recognition/recognition_engine.dart';
import 'package:rafiq/data/khatm.dart';
import 'package:rafiq/data/note.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/data/settings.dart';
import 'package:rafiq/data/surah_names.dart';
import 'package:rafiq/services/screen_awake.dart';
import 'package:rafiq/services/server_health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rafiq/services/sharer.dart';

class FakeAudioSource implements AudioSource {
  bool permission = true;
  bool failOnStart = false;
  int starts = 0;
  int stops = 0;
  StreamController<Float32List>? _controller;

  bool get capturing => _controller != null;

  @override
  Future<bool> ensurePermission() async => permission;

  @override
  Future<Stream<Float32List>> start() async {
    if (failOnStart) throw StateError('no mic');
    starts++;
    _controller = StreamController<Float32List>();
    return _controller!.stream;
  }

  void push(Float32List samples) => _controller?.add(samples);

  void breakMic() => _controller?.addError(StateError('mic unplugged'));

  @override
  Future<void> stop() async {
    stops++;
    final c = _controller;
    _controller = null;
    await c?.close();
  }

  @override
  Future<void> dispose() async {}
}

class FakeEngine implements RecognitionEngine {
  final _events = StreamController<RecognitionEvent>.broadcast(sync: true);
  Hint? startedWith;
  bool started = false;
  bool finished = false;
  bool cancelled = false;
  bool disposed = false;
  int samples = 0;

  void emit(RecognitionEvent event) => _events.add(event);

  @override
  Stream<RecognitionEvent> get events => _events.stream;

  @override
  Future<void> start({Hint? hint}) async {
    started = true;
    startedWith = hint;
  }

  @override
  void addAudio(Float32List s) => samples += s.length;

  final locks = <Hint?>[];
  final positions = <int>[];

  @override
  void lock(Hint? scope) => locks.add(scope);

  @override
  void setPosition(int verseId) => positions.add(verseId);

  @override
  Future<void> finish() async {
    finished = true;
    emit(const EngineDone());
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}

class FakeSharer implements Sharer {
  final texts = <String>[];
  final images = <({int bytes, String fileName, String? text})>[];

  @override
  Future<void> shareText(String text) async => texts.add(text);

  @override
  Future<void> shareImage(Uint8List png, {required String fileName, String? text}) async =>
      images.add((bytes: png.length, fileName: fileName, text: text));
}

class FakeScreenAwake implements ScreenAwake {
  bool enabled = false;

  @override
  Future<void> enable() async => enabled = true;

  @override
  Future<void> disable() async => enabled = false;
}

/// A store whose writes fail (a full disk): reads still work.
class FailingStore implements ReadingStore {
  FailingStore(this._inner);
  final ReadingStore _inner;
  bool failing = true;

  @override
  SavedPosition? readingPosition() => _inner.readingPosition();
  @override
  Future<bool> saveReadingPosition(SavedPosition p) async => !failing && await _inner.saveReadingPosition(p);
  @override
  SavedPosition? taraweehPosition() => _inner.taraweehPosition();
  @override
  Future<bool> saveTaraweehPosition(SavedPosition p) async => !failing && await _inner.saveTaraweehPosition(p);
  @override
  List<Bookmark> bookmarks() => _inner.bookmarks();
  @override
  Future<bool> saveBookmarks(List<Bookmark> b) async => !failing && await _inner.saveBookmarks(b);
  @override
  ReadingLog readingLog() => _inner.readingLog();
  @override
  Future<bool> saveReadingLog(ReadingLog log) async => !failing && await _inner.saveReadingLog(log);
  @override
  ReadingLog pendingReading() => _inner.pendingReading();
  @override
  Future<bool> savePendingReading(ReadingLog p) async => !failing && await _inner.savePendingReading(p);
  @override
  KhatmBook khatm() => _inner.khatm();
  @override
  Future<bool> saveKhatm(KhatmBook book) async => !failing && await _inner.saveKhatm(book);
  @override
  List<Note> notes() => _inner.notes();
  @override
  Future<bool> saveNotes(List<Note> notes) async => !failing && await _inner.saveNotes(notes);
}

Quran? _quran;
Quran loadQuran() => _quran ??= Quran.fromJson(File('assets/quran/quran.json').readAsStringSync());

SurahNames? _names;
SurahNames loadSurahNames() =>
    _names ??= SurahNames.fromJson(File('assets/data/surah-names.json').readAsStringSync(), loadQuran());

/// Everything a test needs, wired the way main.dart wires the real app.
class Harness {
  Harness._(this.prefs);

  final SharedPreferences prefs;
  final audio = FakeAudioSource();
  final awake = FakeScreenAwake();
  final sharer = FakeSharer();
  final engines = <FakeEngine>[];
  final addresses = <String>[];
  ServerHealth health = const ServerHealth.ok(latency: Duration(milliseconds: 12), asr: true, device: 'cuda');

  /// Replace before launching to test storage failures.
  ReadingStore? readingStore;

  /// The time the app sees (change it to cross midnight).
  DateTime now = DateTime(2026, 11, 4, 20);

  FakeEngine get engine => engines.last;

  static Future<Harness> create({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    return Harness._(await SharedPreferences.getInstance());
  }

  List<Override> get overrides => [
        quranProvider.overrideWithValue(loadQuran()),
        surahTableProvider.overrideWithValue(loadSurahNames()),
        settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
        readingStoreProvider.overrideWithValue(readingStore ?? PrefsReadingStore(prefs)),
        audioSourceProvider.overrideWithValue(audio),
        screenAwakeProvider.overrideWithValue(awake),
        sharerProvider.overrideWithValue(sharer),
        clockProvider.overrideWithValue(() => now),
        healthCheckerProvider.overrideWithValue((_) async => health),
        engineFactoryProvider.overrideWithValue((address) {
          addresses.add(address);
          final e = FakeEngine();
          engines.add(e);
          return e;
        }),
      ];

  ProviderContainer container() => ProviderContainer(overrides: overrides);
}

/// A tracker state at `surah:ayah` (verse ids computed from the real Quran).
TrackState at(int surah, int ayah,
    {TrackStatus status = TrackStatus.tracking, double confidence = 0.9, Position? upcoming}) {
  final s = loadQuran().surah(surah);
  return TrackState(
    position: Position(verseId: s.firstVerseId + ayah - 1, surah: surah, ayah: ayah),
    status: status,
    confidence: confidence,
    upcoming: upcoming,
  );
}

Position pos(int surah, int ayah) => at(surah, ayah).position!;

Heard heard(TrackState state, {bool isFinal = true, String text = 'نص'}) =>
    Heard(text: text, start: 0, end: 1, asrMs: 100, state: state, isFinal: isFinal);
