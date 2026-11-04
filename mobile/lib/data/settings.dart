import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// User settings. Immutable; changed through [SettingsStore].
class AppSettings {
  const AppSettings({
    this.serverAddress = defaultServerAddress,
    this.keepScreenOn = true,
    this.textScale = 1.0,
    this.showDiagnostics = false,
    this.themeMode = ThemeMode.system,
    this.darkDuringTaraweeh = true,
    this.taraweehIntroSeen = false,
  });

  /// The Android emulator's alias for the host machine. On a real phone this
  /// becomes the laptop's Wi-Fi address (the server prints it).
  static const defaultServerAddress = '10.0.2.2:8765';

  final String serverAddress;
  final bool keepScreenOn;

  /// Multiplier for Quran text size, [minTextScale] .. [maxTextScale]: the
  /// range validated with the Quran font (shaping, marks, line breaks).
  final double textScale;

  static const minTextScale = 0.85;
  static const maxTextScale = 1.6;

  /// Show the live transcript feed (for field testing).
  final bool showDiagnostics;

  /// The reader follows the phone by default. A value saved by an earlier
  /// version (which defaulted to dark) is kept as it is.
  final ThemeMode themeMode;

  /// Taraweeh mode is always dark, whatever [themeMode]: it is at night, in
  /// a dim prayer hall.
  final bool darkDuringTaraweeh;

  /// The first-run Taraweeh introduction (microphone, Ḥafṣ only, where to
  /// put the phone) has been shown. It is never shown again.
  final bool taraweehIntroSeen;

  AppSettings copyWith({
    String? serverAddress,
    bool? keepScreenOn,
    double? textScale,
    bool? showDiagnostics,
    ThemeMode? themeMode,
    bool? darkDuringTaraweeh,
    bool? taraweehIntroSeen,
  }) =>
      AppSettings(
        serverAddress: serverAddress ?? this.serverAddress,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        textScale: textScale ?? this.textScale,
        showDiagnostics: showDiagnostics ?? this.showDiagnostics,
        themeMode: themeMode ?? this.themeMode,
        darkDuringTaraweeh: darkDuringTaraweeh ?? this.darkDuringTaraweeh,
        taraweehIntroSeen: taraweehIntroSeen ?? this.taraweehIntroSeen,
      );
}

/// Persists [AppSettings] in shared preferences.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _server = 'server_address';
  static const _keepOn = 'keep_screen_on';
  static const _scale = 'text_scale';
  static const _diag = 'show_diagnostics';
  static const _theme = 'theme_mode';
  static const _darkTaraweeh = 'dark_during_taraweeh';
  static const _introSeen = 'taraweeh_intro_seen';

  AppSettings load() {
    const d = AppSettings();
    return AppSettings(
      serverAddress: _prefs.getString(_server) ?? d.serverAddress,
      keepScreenOn: _prefs.getBool(_keepOn) ?? d.keepScreenOn,
      textScale: (_prefs.getDouble(_scale) ?? d.textScale)
          .clamp(AppSettings.minTextScale, AppSettings.maxTextScale)
          .toDouble(),
      showDiagnostics: _prefs.getBool(_diag) ?? d.showDiagnostics,
      themeMode: ThemeMode.values.asNameMap()[_prefs.getString(_theme)] ?? d.themeMode,
      darkDuringTaraweeh: _prefs.getBool(_darkTaraweeh) ?? d.darkDuringTaraweeh,
      taraweehIntroSeen: _prefs.getBool(_introSeen) ?? d.taraweehIntroSeen,
    );
  }

  Future<void> save(AppSettings s) async {
    await _prefs.setString(_server, s.serverAddress.trim());
    await _prefs.setBool(_keepOn, s.keepScreenOn);
    await _prefs.setDouble(_scale, s.textScale);
    await _prefs.setBool(_diag, s.showDiagnostics);
    await _prefs.setString(_theme, s.themeMode.name);
    await _prefs.setBool(_darkTaraweeh, s.darkDuringTaraweeh);
    await _prefs.setBool(_introSeen, s.taraweehIntroSeen);
  }
}
