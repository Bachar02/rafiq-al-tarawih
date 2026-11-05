/// Localized strings: `context.l10n.someKey`. The strings live in the ARB
/// files beside this one; `flutter gen-l10n` (run by `flutter pub get`)
/// writes `generated/`.
library;

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Arabic is never letter-spaced or capitalised (brand book §4).
  bool get isArabic => Localizations.localeOf(this).languageCode == 'ar';
}

/// The first of the phone's languages Rafiq has, else English.
Locale resolveAppLocale(List<Locale> preferred) {
  for (final locale in preferred) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
  }
  return const Locale('en');
}
