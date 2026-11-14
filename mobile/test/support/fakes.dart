/// Test doubles for the app's seams (see docs/DESIGN.md §4.2).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/core/audio/audio_source.dart';
import 'package:rafiq/core/engine/quran_index.dart';
import 'package:rafiq/core/engine/tracker.dart' show TrackerState;
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/core/recognition/recognition_engine.dart';
import 'package:rafiq/data/adhkar.dart';
import 'package:rafiq/data/cities.dart';
import 'package:rafiq/data/duas.dart';
import 'package:rafiq/data/khatm.dart';
import 'package:rafiq/data/note.dart';
import 'package:rafiq/data/prayer_settings.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/data/settings.dart';
import 'package:rafiq/data/study_text.dart';
import 'package:rafiq/data/taraweeh_ledger.dart';
import 'package:rafiq/data/surah_names.dart';
import 'package:rafiq/services/backup_files.dart';
import 'package:rafiq/services/location.dart';
import 'package:rafiq/services/reminders.dart';
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

/// The phone's notifications: what was asked and what is scheduled.
class FakeReminders implements Reminders {
  bool allow = true;
  int asked = 0;

  /// Daily reading reminders.
  int replaced = 0;
  List<Reminder> scheduled = const [];
  String? channel;

  /// Dhikr reminders: the rule the phone was last given.
  int dhikrReplaced = 0;
  DhikrPlan dhikr = DhikrPlan.off;
  String? dhikrChannel;

  /// The adhans.
  int adhanReplaced = 0;
  List<Reminder> adhan = const [];

  /// Whether Android lets notifications come on the minute, how often the
  /// user was sent to its setting, and what they do there.
  bool exact = true;
  int exactAsked = 0;
  bool grantExact = true;

  /// Notifications shown at once (the adhan's test).
  final shown = <Reminder>[];

  /// The dhikr's card on the screen ("Appear on top"): whether Android
  /// allows it, how often the user was sent to its setting, what they do
  /// there, and the adhkar shown at once.
  bool onScreen = false;
  int onScreenAsked = 0;
  bool grantOnScreen = true;

  /// "Show one now": the plan each was drawn from.
  final dhikrShown = <DhikrPlan>[];
  String? closeLabel;

  void Function(String payload)? _onOpen;

  /// The user taps a notification carrying [payload].
  void tap(String payload) => _onOpen?.call(payload);

  @override
  Future<bool> requestPermission() async {
    asked++;
    return allow;
  }

  @override
  Future<void> replace(
    List<Reminder> reminders, {
    required String channelName,
    ReminderKind kind = ReminderKind.reading,
  }) async {
    switch (kind) {
      case ReminderKind.reading:
        replaced++;
        scheduled = List.of(reminders);
        channel = channelName;
      case ReminderKind.adhan:
        adhanReplaced++;
        adhan = List.of(reminders);
    }
  }

  @override
  Future<void> scheduleDhikr(DhikrPlan plan, {required String channelName, required String closeLabel}) async {
    dhikrReplaced++;
    dhikr = plan;
    dhikrChannel = channelName;
    this.closeLabel = closeLabel;
  }

  @override
  Future<bool> allowed() async => allow;

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<bool> requestExact() async {
    exactAsked++;
    if (grantExact) exact = true;
    return exact;
  }

  @override
  Future<void> show(Reminder reminder) async => shown.add(reminder);

  @override
  Future<bool> canShowOnScreen() async => onScreen;

  @override
  Future<bool> requestShowOnScreen() async {
    onScreenAsked++;
    onScreen = grantOnScreen;
    return onScreen;
  }

  @override
  Future<void> showDhikr(DhikrPlan plan, {required String channelName, required String closeLabel}) async =>
      dhikrShown.add(plan);

  @override
  Future<void> onOpen(void Function(String payload) handler) async => _onOpen = handler;
}

/// The phone's file picker: what was saved, and what a picked file holds.
class FakeBackupFiles implements BackupFiles {
  /// Files saved, by name.
  final saved = <String, String>{};

  /// What the user picks when asked to open a file (null: they cancel).
  String? picked;

  /// The user cancels the "Save to" screen.
  bool cancelSave = false;

  @override
  bool canOpen = true;

  @override
  Future<bool> save(String name, String text) async {
    if (cancelSave) return false;
    saved[name] = text;
    return true;
  }

  @override
  Future<String?> open() async => picked;
}

/// The phone's location: what it answers, and what was asked of it.
class FakeLocation implements LocationSource {
  /// What [locate] answers: Tunis, until a test says otherwise.
  LocationResult result = const LocationResult.found(36.8065, 10.1815);

  /// What the phone already knows, without asking (null: nothing, or the
  /// app may not read it).
  LocationResult? known;

  int located = 0;
  final settingsOpened = <LocationFailure>[];

  @override
  Future<LocationResult> locate() async {
    located++;
    return result;
  }

  @override
  Future<LocationResult?> lastKnown() async => known;

  @override
  Future<void> openSettings(LocationFailure failure) async => settingsOpened.add(failure);
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
  TaraweehLedger? taraweehLedger() => _inner.taraweehLedger();
  @override
  Future<bool> saveTaraweehLedger(TaraweehLedger l) async => !failing && await _inner.saveTaraweehLedger(l);
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

/// The recognition engine's index of [quran] (its words, and its surahs).
QuranIndex indexOf(Quran quran) =>
    QuranIndex([for (final v in quran.verses) v.text], surahStarts: [for (final s in quran.surahs) s.firstVerseId]);

SurahNames? _names;
SurahNames loadSurahNames() =>
    _names ??= SurahNames.fromJson(File('assets/data/surah-names.json').readAsStringSync(), loadQuran());

Adhkar? _adhkar;
Adhkar loadAdhkar() => _adhkar ??= Adhkar.fromJson(File('assets/adhkar/adhkar.json').readAsStringSync(), loadQuran());

Duas? _duas;

/// The bundled duas, read from the file (parsed once per test run).
Duas loadDuas() => _duas ??= Duas.fromJson(File('assets/duas/duas.json').readAsStringSync(), loadQuran());

Cities? _cities;

/// The bundled towns, read from the files (parsed once per test run).
Cities loadCities() => _cities ??= Cities.parse((
      cities: File('assets/places/cities.tsv').readAsStringSync(),
      countries: File('assets/places/countries.tsv').readAsStringSync(),
    ));

/// The phone's clock in the tests: an hour ahead of UTC all year (Tunis),
/// whatever the time zone of the machine that runs them.
DateTime tunisClock(DateTime utc) {
  final t = utc.toUtc().add(const Duration(hours: 1));
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
}

StudyCatalog? _catalog;
StudyCatalog loadStudyCatalog() =>
    _catalog ??= StudyCatalog.fromJson(File('assets/texts/catalog.json').readAsStringSync());

final _texts = <String, StudyText>{};

/// The bundled texts, read from the files (parsed once per test run).
Future<StudyText> loadStudyTextFile(StudySource source) async =>
    _texts[source.key] ??= StudyText.parse((raw: File(source.asset).readAsStringSync(), key: source.key));

/// Everything a test needs, wired the way main.dart wires the real app.
class Harness {
  Harness._(this.prefs);

  final SharedPreferences prefs;
  final audio = FakeAudioSource();
  final awake = FakeScreenAwake();
  final sharer = FakeSharer();
  final reminders = FakeReminders();
  final location = FakeLocation();
  final backupFiles = FakeBackupFiles();
  final engines = <FakeEngine>[];
  final addresses = <String>[];
  ServerHealth health = const ServerHealth.ok(latency: Duration(milliseconds: 12), asr: true, device: 'cuda');

  /// Replace before launching to make texts fail or wait.
  StudyTextLoader studyTexts = loadStudyTextFile;

  /// Replace before launching to test storage failures.
  ReadingStore? readingStore;

  /// The time the app sees (change it to cross midnight).
  DateTime now = defaultNow;

  /// What [now] starts at: an evening, 20:00.
  static final defaultNow = DateTime(2026, 11, 4, 20);

  FakeEngine get engine => engines.last;

  static Future<Harness> create({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    return Harness._(await SharedPreferences.getInstance());
  }

  List<Override> get overrides => [
        quranProvider.overrideWithValue(loadQuran()),
        surahTableProvider.overrideWithValue(loadSurahNames()),
        studyCatalogProvider.overrideWithValue(loadStudyCatalog()),
        preferencesProvider.overrideWithValue(prefs),
        backupFilesProvider.overrideWithValue(backupFiles),
        adhkarProvider.overrideWithValue(loadAdhkar()),
        duasProvider.overrideWithValue(loadDuas()),
        adhkarStoreProvider.overrideWithValue(AdhkarStore(prefs)),
        prayerStoreProvider.overrideWithValue(PrayerSettingsStore(prefs)),
        citiesLoaderProvider.overrideWithValue(() async => loadCities()),
        locationProvider.overrideWithValue(location),
        wallClockProvider.overrideWithValue(tunisClock),
        studyTextLoaderProvider.overrideWithValue((s) => studyTexts(s)),
        settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
        readingStoreProvider.overrideWithValue(readingStore ?? PrefsReadingStore(prefs)),
        audioSourceProvider.overrideWithValue(audio),
        screenAwakeProvider.overrideWithValue(awake),
        sharerProvider.overrideWithValue(sharer),
        remindersProvider.overrideWithValue(reminders),
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
/// `evidence: false` is a miss: the engine holding this position, no news.
TrackState at(int surah, int ayah,
    {TrackStatus status = TrackStatus.tracking, double confidence = 0.9, Position? upcoming, bool evidence = true}) {
  final s = loadQuran().surah(surah);
  return TrackState(
    position: Position(verseId: s.firstVerseId + ayah - 1, surah: surah, ayah: ayah),
    status: status,
    confidence: confidence,
    upcoming: upcoming,
    evidence: evidence,
  );
}

Position pos(int surah, int ayah) => at(surah, ayah).position!;

Heard heard(TrackState state, {bool isFinal = true, String text = 'نص'}) =>
    Heard(text: text, start: 0, end: 1, asrMs: 100, state: state, isFinal: isFinal);

/// A tie report as an engine sends it: repeated words fitting every
/// `(surah, ayah)` in [refs] as well (Quran order), at cold start unless
/// [position] holds an earlier one. `trusted: false` is a tie the engine
/// would not rely on; `evidence: false` the same report held through a miss.
TrackState tie(
  List<(int, int)> refs, {
  bool trusted = true,
  Position? position,
  bool evidence = true,
  TrackStatus status = TrackStatus.uncertain,
}) =>
    TrackState(
      status: status,
      position: position,
      evidence: evidence,
      tied: [for (final (s, a) in refs) pos(s, a)],
      tieTrusted: trusted,
    );

/// The app's view of the real tracker's [state], as the on-device engine
/// converts it.
TrackState fromEngine(TrackerState state) {
  final quran = loadQuran();
  Position? p(int? id) {
    if (id == null) return null;
    final v = quran.verse(id);
    return Position(verseId: id, surah: v.surah, ayah: v.ayah);
  }

  return TrackState(
    status: TrackStatus.parse(state.status.name),
    position: p(state.verseId),
    confidence: state.confidence,
    pending: p(state.pendingVerse),
    alternatives: [for (final a in state.alternatives) p(a)!],
    upcoming: p(state.upcomingVerse),
    evidence: state.evidence,
    tied: [for (final v in state.tied) p(v)!],
    tieTrusted: state.tieTrusted,
  );
}
