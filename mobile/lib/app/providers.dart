/// Dependency wiring. Every platform or network dependency is a provider, so
/// tests override it with a fake and Phase 6 swaps the engine in one place.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_source.dart';
import '../core/recognition/recognition_engine.dart';
import '../data/quran.dart';
import '../data/reading_store.dart';
import '../data/settings.dart';
import '../data/surah_names.dart';
import '../l10n/l10n.dart';
import '../features/listen/listen_controller.dart';
import '../features/listen/listen_state.dart';
import '../features/listen/taraweeh_position.dart';
import '../features/reader/bookmarks.dart';
import '../features/reader/reading_position.dart';
import '../features/search/quran_search.dart';
import '../services/mic_audio_source.dart';
import '../services/screen_awake.dart';
import '../services/server_health.dart';
import '../services/server_recognition_engine.dart';
import '../services/sharer.dart';
import '../features/reader/reading_progress.dart';

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

/// Pages read each day, for the daily goal.
final readingProgressProvider = NotifierProvider<ReadingProgressController, ReadingLog>(ReadingProgressController.new);

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

/// The phone's share sheet (tests override it).
final sharerProvider = Provider<Sharer>((ref) => const PlatformSharer());

final screenAwakeProvider = Provider<ScreenAwake>((ref) => const WakelockScreenAwake());

final healthCheckerProvider = Provider<HealthChecker>((ref) => checkServerHealth);

final listenControllerProvider = NotifierProvider<ListenController, ListenState>(ListenController.new);

/// Where Taraweeh last got to (independent of the reading position).
final taraweehPositionProvider =
    NotifierProvider<TaraweehPositionController, SavedPosition?>(TaraweehPositionController.new);
