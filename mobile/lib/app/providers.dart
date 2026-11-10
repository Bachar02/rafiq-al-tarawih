/// Dependency wiring. Every platform or network dependency is a provider, so
/// tests override it with a fake and Phase 6 swaps the engine in one place.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_source.dart';
import '../core/recognition/recognition_engine.dart';
import '../data/adhkar.dart';
import '../data/cities.dart';
import '../data/khatm.dart';
import '../data/note.dart';
import '../data/prayer_settings.dart';
import '../data/quran.dart';
import '../data/reading_stats.dart';
import '../data/reading_store.dart';
import '../data/settings.dart';
import '../data/study_text.dart';
import '../data/surah_names.dart';
import '../l10n/l10n.dart';
import '../features/adhkar/adhkar_controller.dart';
import '../features/adhkar/dhikr_reminders.dart';
import '../features/khatm/khatm_controller.dart';
import '../features/progress/reminder.dart';
import '../features/listen/listen_controller.dart';
import '../features/notes/notes_controller.dart';
import '../features/prayer/adhan_sync.dart';
import '../features/prayer/prayer_controller.dart';
import '../features/listen/listen_state.dart';
import '../features/listen/taraweeh_position.dart';
import '../features/reader/bookmarks.dart';
import '../features/reader/reading_position.dart';
import '../features/search/quran_search.dart';
import '../services/location.dart';
import '../services/mic_audio_source.dart';
import '../services/reminders.dart';
import '../services/screen_awake.dart';
import '../services/server_health.dart';
import '../services/server_recognition_engine.dart';
import '../services/sharer.dart';
import '../features/reader/reading_progress.dart';
import '../features/reader/reading_session.dart';

/// Loaded once at startup (see main.dart) and injected with an override.
final quranProvider = Provider<Quran>((ref) => throw UnimplementedError('quranProvider must be overridden'));

/// Curated surah display names. main.dart overrides this with the bundled
/// table; without it, the Quran data's own transliteration is used.
final surahTableProvider = Provider<SurahNames>((ref) => SurahNames.fallback(ref.watch(quranProvider)));

/// The interface locale: the user's choice, or the phone's language if
/// Rafiq has it, else English. The one place the app decides its language.
final appLocaleProvider = Provider<Locale>((ref) {
  final chosen = ref.watch(settingsProvider.select((s) => s.language)).locale;
  return chosen ?? resolveAppLocale(WidgetsBinding.instance.platformDispatcher.locales);
});

/// Surah names in the interface language (Arabic: each surah's own name).
final surahNamesProvider = Provider<SurahNames>((ref) {
  final language = NameLanguage.values.asNameMap()[ref.watch(appLocaleProvider).languageCode] ?? NameLanguage.en;
  return ref.watch(surahTableProvider).inLanguage(language);
});

/// The bundled translations and tafsirs (main.dart loads the catalog; the
/// texts themselves load on first use).
final studyCatalogProvider = Provider<StudyCatalog>((ref) => StudyCatalog.empty);

/// Reads one bundled text (tests replace it to read from files, or to fail).
final studyTextLoaderProvider = Provider<StudyTextLoader>((ref) => loadBundledStudyText);

/// A whole translation or tafsir, by key: loaded once, then kept.
final studyTextProvider = FutureProvider.family<StudyText, String>((ref, key) {
  final source = ref.watch(studyCatalogProvider).byKey(key);
  if (source == null) throw ArgumentError.value(key, 'key', 'not a bundled text');
  return ref.watch(studyTextLoaderProvider)(source);
  // A bundled file that fails to parse will not parse on a second try.
}, retry: (_, __) => null);

/// The translation or tafsir shown: the user's choice, else one in the
/// interface language (see [StudyCatalog.pick]). Null if none is bundled.
final studySourceProvider = Provider.family<StudySource?, StudyKind>((ref, kind) {
  final settings = ref.watch(settingsProvider);
  return ref.watch(studyCatalogProvider).pick(
        kind,
        languageCode: ref.watch(appLocaleProvider).languageCode,
        chosen: kind == StudyKind.translation ? settings.translationKey : settings.tafsirKey,
      );
});

/// The bundled adhkar (main.dart loads them; without them the Adhkar screen
/// is empty and nothing else changes).
final adhkarProvider = Provider<Adhkar>((ref) => Adhkar.empty);

/// Loaded once at startup (see main.dart) and injected with an override.
final adhkarStoreProvider =
    Provider<AdhkarStore>((ref) => throw UnimplementedError('adhkarStoreProvider must be overridden'));

/// Today's adhkar counts.
final adhkarDayProvider = NotifierProvider<AdhkarDayController, AdhkarDay>(AdhkarDayController.new);

/// Loaded once at startup (see main.dart) and injected with an override.
final settingsStoreProvider =
    Provider<SettingsStore>((ref) => throw UnimplementedError('settingsStoreProvider must be overridden'));

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Loaded once at startup (see main.dart) and injected with an override.
final readingStoreProvider =
    Provider<ReadingStore>((ref) => throw UnimplementedError('readingStoreProvider must be overridden'));

/// The personal reading position (verse id at the top of the reader).
final readingPositionProvider = NotifierProvider<ReadingPositionController, int>(ReadingPositionController.new);

/// Search over the bundled Quran (its text index is built on first use).
final quranSearchProvider =
    Provider<QuranSearch>((ref) => QuranSearch(ref.watch(quranProvider), ref.watch(surahNamesProvider)));

/// The time (tests replace it to cross midnight without waiting).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// What the reader proposes as read (time on the page), waiting for the
/// user's review.
final readingSessionProvider = NotifierProvider<ReadingSessionController, ReadingSession>(ReadingSessionController.new);

/// Pages read each day, as the user counted them: the daily goal.
final readingProgressProvider = NotifierProvider<ReadingProgressController, ReadingLog>(ReadingProgressController.new);

/// What the reading chart shows: pages per day (counted, and waiting for
/// review), runs and totals, as of the last change.
final readingStatsProvider = Provider<ReadingStats>(
  (ref) => ReadingStats(
    ref.watch(readingProgressProvider),
    ref.watch(readingSessionProvider.select((s) => s.pending)),
    ref.read(clockProvider)(),
  ),
);

/// Keeps the scheduled daily reminders in step with the app.
final reminderSyncProvider = Provider<ReminderSync>(ReminderSync.new);

/// Keeps the scheduled dhikr reminders in step with the app.
final dhikrSyncProvider = Provider<DhikrSync>(DhikrSync.new);

/// Loaded once at startup (see main.dart) and injected with an override.
final prayerStoreProvider =
    Provider<PrayerSettingsStore>((ref) => throw UnimplementedError('prayerStoreProvider must be overridden'));

/// The place the prayer times are for, how they are computed, and how each
/// prayer's adhan is called.
final prayerSettingsProvider = NotifierProvider<PrayerSettingsController, PrayerSettings>(PrayerSettingsController.new);

/// Reads the bundled list of towns (tests replace it to read from files).
final citiesLoaderProvider = Provider<Future<Cities> Function()>((ref) => loadBundledCities);

/// The towns a place can be chosen from, and that name a position: read
/// the first time a place is set, then kept. Empty if the list cannot be
/// read: a position still gives prayer times, named by its coordinates.
final citiesProvider = FutureProvider<Cities>((ref) async {
  try {
    return await ref.watch(citiesLoaderProvider)();
  } catch (e, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'prayer times'));
    return Cities.empty;
  }
});

/// The phone's location, read once when the user asks (tests override it).
final locationProvider = Provider<LocationSource>((ref) => const DeviceLocation());

/// What the phone's clock shows for an instant (tests fix the time zone).
final wallClockProvider = Provider<DateTime Function(DateTime utc)>((ref) => (utc) => utc.toLocal());

/// Keeps the scheduled adhans in step with the app.
final adhanSyncProvider = Provider<AdhanSync>(AdhanSync.new);

/// Whether Android lets the adhan be shown, and on the minute. Read again
/// when the app comes back from the phone's settings.
final adhanStatusProvider = FutureProvider.autoDispose<AdhanStatus>((ref) async {
  final reminders = ref.watch(remindersProvider);
  return (allowed: await reminders.allowed(), exact: await reminders.canScheduleExact());
});

/// The khatm plan, if one is running, and the finished khatms.
final khatmProvider = NotifierProvider<KhatmController, KhatmBook>(KhatmController.new);

/// The user's notes, newest edit first, one per ayah.
final notesProvider = NotifierProvider<NotesController, List<Note>>(NotesController.new);

/// Bookmarked ayahs, newest first.
final bookmarksProvider = NotifierProvider<BookmarksController, List<Bookmark>>(BookmarksController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsStoreProvider).load();

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsStoreProvider).save(state);
  }
}

final audioSourceProvider = Provider<AudioSource>((ref) {
  final source = MicAudioSource();
  ref.onDispose(source.dispose);
  return source;
});

final engineFactoryProvider = Provider<RecognitionEngineFactory>(
  (ref) => (address) => ServerRecognitionEngine(address),
);

/// The phone's notifications: the daily reading reminder, dhikr reminders
/// and the adhan (tests override it).
final remindersProvider = Provider<Reminders>((ref) => LocalReminders());

/// The phone's share sheet (tests override it).
final sharerProvider = Provider<Sharer>((ref) => const PlatformSharer());

final screenAwakeProvider = Provider<ScreenAwake>((ref) => const WakelockScreenAwake());

final healthCheckerProvider = Provider<HealthChecker>((ref) => checkServerHealth);

final listenControllerProvider = NotifierProvider<ListenController, ListenState>(ListenController.new);

/// Where Taraweeh last got to (independent of the reading position).
final taraweehPositionProvider =
    NotifierProvider<TaraweehPositionController, SavedPosition?>(TaraweehPositionController.new);
