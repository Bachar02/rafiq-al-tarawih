import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/quran.dart';
import 'data/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // ~1 MB of JSON: parse off the UI thread so startup never janks.
    final raw = await rootBundle.loadString('assets/quran/quran.json');
    final quran = await compute(Quran.fromJson, raw);
    final prefs = await SharedPreferences.getInstance();
    runApp(
      ProviderScope(
        overrides: [
          quranProvider.overrideWithValue(quran),
          settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
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

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
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
