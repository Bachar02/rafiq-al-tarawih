/// Dependency wiring. Every platform or network dependency is a provider, so
/// tests override it with a fake and Phase 6 swaps the engine in one place.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_source.dart';
import '../core/recognition/recognition_engine.dart';
import '../data/quran.dart';
import '../data/settings.dart';
import '../data/surah_names.dart';
import '../features/listen/listen_controller.dart';
import '../features/listen/listen_state.dart';
import '../services/mic_audio_source.dart';
import '../services/screen_awake.dart';
import '../services/server_health.dart';
import '../services/server_recognition_engine.dart';

/// Loaded once at startup (see main.dart) and injected with an override.
final quranProvider = Provider<Quran>((ref) => throw UnimplementedError('quranProvider must be overridden'));

/// Curated surah display names. main.dart overrides this with the bundled
/// table; without it, the Quran data's own transliteration is used.
final surahNamesProvider = Provider<SurahNames>((ref) => SurahNames.fallback(ref.watch(quranProvider)));

/// Loaded once at startup (see main.dart) and injected with an override.
final settingsStoreProvider =
    Provider<SettingsStore>((ref) => throw UnimplementedError('settingsStoreProvider must be overridden'));

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

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

final screenAwakeProvider = Provider<ScreenAwake>((ref) => const WakelockScreenAwake());

final healthCheckerProvider = Provider<HealthChecker>((ref) => checkServerHealth);

final listenControllerProvider = NotifierProvider<ListenController, ListenState>(ListenController.new);
