/// Every screen-to-screen move, in one place: screens never build each
/// other's routes, and the names make navigation visible in tests and logs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/listen/listen_screen.dart';
import '../features/listen/widgets/surah_index.dart';
import '../features/settings/settings_screen.dart';
import 'providers.dart';
import 'theme.dart';

abstract final class AppRoutes {
  static const settingsName = '/settings';
  static const taraweehName = '/taraweeh';
  static const navigateName = '/navigate';

  /// A route that keeps the theme it was opened from: settings opened in
  /// (dark) Taraweeh mode stay dark, as do their sheets and dialogs.
  static Route<T> _route<T>(BuildContext context, String name, WidgetBuilder builder) {
    final themes = InheritedTheme.capture(from: context, to: Navigator.of(context).context);
    return MaterialPageRoute<T>(settings: RouteSettings(name: name), builder: (c) => themes.wrap(builder(c)));
  }

  static Future<void> settings(BuildContext context) =>
      Navigator.of(context).push(_route<void>(context, settingsName, (_) => const SettingsScreen()));

  /// Taraweeh mode, full screen over the reader.
  static Future<void> taraweeh(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: taraweehName),
          builder: (_) => const TaraweehTheme(child: ListenScreen()),
        ),
      );

  /// Choose a place to read; returns its verse id, or null.
  static Future<int?> navigate(BuildContext context, {required int current}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final quran = container.read(quranProvider);
    final surah = await showSurahIndex(
      context,
      quran: quran,
      names: container.read(surahNamesProvider),
      current: quran.verse(current).surah,
    );
    return surah == null ? null : quran.surah(surah).firstVerseId;
  }
}

/// Taraweeh mode's theme: dark whatever the reader uses, unless the user
/// turned "Dark during Taraweeh" off. Scoped to the mode's route, so the
/// reader underneath never changes and nothing global has to be undone.
class TaraweehTheme extends ConsumerWidget {
  const TaraweehTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(settingsProvider.select((s) => s.darkDuringTaraweeh));
    if (!dark) return child;
    return Theme(
      data: AppTheme.dark(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: child),
    );
  }
}
