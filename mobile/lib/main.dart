import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/app_scope.dart';
import 'app/providers.dart';
import 'app/theme.dart';
import 'data/adhkar.dart';
import 'data/duas.dart';
import 'data/prayer_settings.dart';
import 'data/quran.dart';
import 'data/reading_store.dart';
import 'data/settings.dart';
import 'data/study_text.dart';
import 'data/surah_names.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // ~1 MB of JSON: parse off the UI thread so startup never janks.
    final raw = await rootBundle.loadString('assets/quran/quran.json');
    final quran = await compute(Quran.fromJson, raw);
    final names = SurahNames.fromJson(await rootBundle.loadString('assets/data/surah-names.json'), quran);
    final texts = StudyCatalog.fromJson(await rootBundle.loadString('assets/texts/catalog.json'));
    final adhkar = await _loadAdhkar(quran);
    final duas = await _loadDuas(quran);
    final prefs = await SharedPreferences.getInstance();
    runApp(
      // A scope that a restored backup can open again from scratch.
      AppScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          quranProvider.overrideWithValue(quran),
          surahTableProvider.overrideWithValue(names),
          studyCatalogProvider.overrideWithValue(texts),
          adhkarProvider.overrideWithValue(adhkar),
          duasProvider.overrideWithValue(duas),
          adhkarStoreProvider.overrideWithValue(AdhkarStore(prefs)),
          prayerStoreProvider.overrideWithValue(PrayerSettingsStore(prefs)),
          settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
          readingStoreProvider.overrideWithValue(PrefsReadingStore(prefs)),
        ],
        child: const RafiqApp(),
      ),
    );
  } catch (e, stack) {
    // A broken install should say so, not show a blank screen.
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack));
    runApp(_StartupError(error: '$e'));
  }
}

/// The adhkar, or none if the file cannot be read: the Quran must open
/// whatever happens to them (the tests check the bundled file).
Future<Adhkar> _loadAdhkar(Quran quran) async {
  try {
    return Adhkar.fromJson(await rootBundle.loadString('assets/adhkar/adhkar.json'), quran);
  } catch (e, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'adhkar'));
    return Adhkar.empty;
  }
}

/// The duas, or none if the file cannot be read (as the adhkar).
Future<Duas> _loadDuas(Quran quran) async {
  try {
    return Duas.fromJson(await rootBundle.loadString('assets/duas/duas.json'), quran);
  } catch (e, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'duas'));
    return Duas.empty;
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Rafiq could not start.\n\n$error', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
