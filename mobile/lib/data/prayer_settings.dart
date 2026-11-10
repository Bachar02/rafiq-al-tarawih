/// What the prayer times are computed for and how the adhan is called: the
/// place, the rules of calculation, and each prayer's alert. One small
/// versioned JSON record, kept on the phone. The place never leaves it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prayer/prayer_times.dart';

/// Where the prayer times are for.
@immutable
class Place {
  const Place({
    required this.names,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.fromLocation,
  });

  /// The place's name by language (`en` always; `fr` and `ar` when known).
  /// For a position found by the phone, the nearest town of the list.
  final Map<String, String> names;

  /// ISO 3166, two letters; null where no country is known (the open sea).
  final String? countryCode;

  final double latitude;
  final double longitude;

  /// Found by the phone's location rather than chosen from the list: it
  /// follows the user when they travel. A chosen place never moves.
  final bool fromLocation;

  String name(String languageCode) => names[languageCode] ?? names['en'] ?? names.values.first;

  Map<String, Object?> toJson() => {
        'names': names,
        'cc': countryCode,
        'lat': latitude,
        'lon': longitude,
        'located': fromLocation,
      };

  /// Null if [json] is not a place on Earth with a name.
  static Place? fromJson(Object? json) {
    if (json is! Map) return null;
    final names = json['names'], lat = json['lat'], lon = json['lon'], cc = json['cc'];
    if (names is! Map || lat is! num || lon is! num) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    final byLanguage = {
      for (final e in names.entries)
        if (e.key is String && e.value is String && (e.value as String).isNotEmpty) e.key as String: e.value as String,
    };
    if (byLanguage.isEmpty) return null;
    return Place(
      names: Map.unmodifiable(byLanguage),
      countryCode: cc is String && cc.length == 2 ? cc.toUpperCase() : null,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      fromLocation: json['located'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Place &&
      mapEquals(other.names, names) &&
      other.countryCode == countryCode &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.fromLocation == fromLocation;

  @override
  int get hashCode => Object.hash(countryCode, latitude, longitude, fromLocation);
}

/// How a prayer's time is announced.
enum AdhanAlert {
  /// Nothing for this prayer.
  off,

  /// A notification, without sound or vibration.
  silent,

  /// A notification and a vibration.
  vibrate,

  /// The adhan.
  sound,
}

/// Which recording the adhan plays (a raw resource of the Android app).
enum AdhanSound {
  /// The whole adhan, about two and a half minutes.
  full('adhan_full'),

  /// Its opening takbir, about half a minute.
  takbir('adhan_takbir');

  const AdhanSound(this.resource);

  /// The file's name in `android/app/src/main/res/raw`, without extension.
  final String resource;
}

/// The prayer times' settings. Immutable; changed through
/// [PrayerSettingsStore].
@immutable
class PrayerSettings {
  const PrayerSettings({
    this.place,
    this.method,
    this.asr,
    this.offsets = const {},
    this.adhanOn = false,
    this.alerts = const {},
    this.sound = AdhanSound.full,
  });

  /// Null until the user gives one: then there are no times to show.
  final Place? place;

  /// The method the user chose; null follows the place's country.
  final PrayerMethod? method;

  /// The school for Asr the user chose; null follows the place's country.
  final AsrSchool? asr;

  /// Minutes added to a time to match the local mosque (absent: none).
  final Map<Prayer, int> offsets;

  /// The adhan as a whole: off until the user turns it on.
  final bool adhanOn;

  /// Each prayer's alert while [adhanOn] (absent: [AdhanAlert.sound]).
  final Map<Prayer, AdhanAlert> alerts;

  final AdhanSound sound;

  PrayerMethod get effectiveMethod => method ?? PrayerMethod.forCountry(place?.countryCode);

  AsrSchool get effectiveAsr => asr ?? AsrSchool.forCountry(place?.countryCode);

  int offsetOf(Prayer prayer) => offsets[prayer] ?? 0;

  /// How [prayer] is announced: off for all while the adhan is off, and
  /// never for the sunrise.
  AdhanAlert alertOf(Prayer prayer) =>
      !adhanOn || !prayer.isCalled ? AdhanAlert.off : alerts[prayer] ?? AdhanAlert.sound;

  /// The prayers' times on the calendar day [day] (its year, month and day
  /// are read; the rest is ignored). Null without a place.
  PrayerDay? timesOn(DateTime day) {
    final p = place;
    if (p == null) return null;
    return prayerDay(
      year: day.year,
      month: day.month,
      day: day.day,
      latitude: p.latitude,
      longitude: p.longitude,
      method: effectiveMethod,
      asr: effectiveAsr,
      offsets: offsets,
    );
  }

  PrayerSettings withPlace(Place? place) => _copy(place: () => place);

  /// [method] null: follow the place's country again.
  PrayerSettings withMethod(PrayerMethod? method) => _copy(method: () => method);

  PrayerSettings withAsr(AsrSchool? asr) => _copy(asr: () => asr);

  PrayerSettings withOffset(Prayer prayer, int minutes) => _copy(
        offsets: () => {
          for (final e in offsets.entries)
            if (e.key != prayer) e.key: e.value,
          if (minutes != 0) prayer: minutes.clamp(-maxPrayerOffset, maxPrayerOffset),
        },
      );

  PrayerSettings withAdhan({required bool on}) => _copy(adhanOn: () => on);

  PrayerSettings withAlert(Prayer prayer, AdhanAlert alert) => _copy(alerts: () => {...alerts, prayer: alert});

  PrayerSettings withSound(AdhanSound sound) => _copy(sound: () => sound);

  PrayerSettings _copy({
    Place? Function()? place,
    PrayerMethod? Function()? method,
    AsrSchool? Function()? asr,
    Map<Prayer, int> Function()? offsets,
    bool Function()? adhanOn,
    Map<Prayer, AdhanAlert> Function()? alerts,
    AdhanSound Function()? sound,
  }) =>
      PrayerSettings(
        place: place == null ? this.place : place(),
        method: method == null ? this.method : method(),
        asr: asr == null ? this.asr : asr(),
        offsets: Map.unmodifiable(offsets == null ? this.offsets : offsets()),
        adhanOn: adhanOn == null ? this.adhanOn : adhanOn(),
        alerts: Map.unmodifiable(alerts == null ? this.alerts : alerts()),
        sound: sound == null ? this.sound : sound(),
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'place': place?.toJson(),
        'method': method?.name,
        'asr': asr?.name,
        'offsets': {for (final e in offsets.entries) e.key.name: e.value},
        'adhan': adhanOn,
        'alerts': {for (final e in alerts.entries) e.key.name: e.value.name},
        'sound': sound.name,
      };

  /// Null if [json] is not a version 1 record. A part that cannot be read
  /// (a method a later version added, say) falls back to its default: the
  /// rest still stands.
  static PrayerSettings? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    final prayers = Prayer.values.asNameMap();
    final offsets = json['offsets'], alerts = json['alerts'];
    return PrayerSettings(
      place: Place.fromJson(json['place']),
      method: PrayerMethod.values.asNameMap()[json['method']],
      asr: AsrSchool.values.asNameMap()[json['asr']],
      offsets: Map.unmodifiable({
        if (offsets is Map)
          for (final e in offsets.entries)
            if (prayers[e.key] != null && e.value is int && e.value != 0)
              prayers[e.key]!: (e.value as int).clamp(-maxPrayerOffset, maxPrayerOffset),
      }),
      adhanOn: json['adhan'] == true,
      alerts: Map.unmodifiable({
        if (alerts is Map)
          for (final e in alerts.entries)
            if (prayers[e.key] != null && prayers[e.key]!.isCalled && AdhanAlert.values.asNameMap()[e.value] != null)
              prayers[e.key]!: AdhanAlert.values.asNameMap()[e.value]!,
      }),
      sound: AdhanSound.values.asNameMap()[json['sound']] ?? AdhanSound.full,
    );
  }
}

/// Keeps [PrayerSettings] on the phone. A record that cannot be read is
/// copied aside before anything is written over it (the rule of
/// `reading_store.dart`): the place and the alerts took the user some care.
class PrayerSettingsStore {
  PrayerSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'prayer.v1';

  Future<bool>? _backup;

  PrayerSettings load() {
    final Object? raw;
    try {
      raw = _prefs.get(key);
    } catch (_) {
      return const PrayerSettings();
    }
    if (raw == null) return const PrayerSettings();
    PrayerSettings? settings;
    if (raw is String) {
      try {
        settings = PrayerSettings.fromJson(jsonDecode(raw));
      } on FormatException {
        settings = null;
      }
    }
    if (settings == null) _setAside(raw);
    return settings ?? const PrayerSettings();
  }

  void _setAside(Object raw) {
    final backup = '$key.unreadable.${DateTime.now().microsecondsSinceEpoch}';
    debugPrint('PrayerSettingsStore: $key is unreadable; kept as $backup');
    _backup ??= _prefs.setString(backup, raw is String ? raw : '$raw').catchError((_) => false);
  }

  /// False if it could not be written (the caller keeps what it shows).
  Future<bool> save(PrayerSettings settings) async {
    final backup = _backup;
    if (backup != null && !await backup) return false;
    try {
      return await _prefs.setString(key, jsonEncode(settings.toJson()));
    } catch (_) {
      return false;
    }
  }
}
