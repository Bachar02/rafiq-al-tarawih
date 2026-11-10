/// Where the phone is, for the prayer times: one approximate position when
/// the user asks for it, read on the phone and kept there. Never in the
/// background, never precise (the manifest asks for the approximate
/// permission only).
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Why no position came back.
enum LocationFailure {
  /// The user said no this time: asking again is fine.
  denied,

  /// The user said no for good: only the phone's settings can change it.
  deniedForever,

  /// Location is turned off for the whole phone.
  serviceOff,

  /// Allowed, but the phone found no position in time (indoors, no network).
  unavailable,
}

/// A position, or why there is none.
class LocationResult {
  const LocationResult.found(double this.latitude, double this.longitude) : failure = null;
  const LocationResult.failed(LocationFailure this.failure)
      : latitude = null,
        longitude = null;

  final double? latitude;
  final double? longitude;
  final LocationFailure? failure;

  bool get found => failure == null;
}

/// The phone's location (tests replace it).
abstract interface class LocationSource {
  /// Asks for permission if needed, then for one approximate position.
  Future<LocationResult> locate();

  /// The position the phone already knows, if the app may read it. Never
  /// asks the user anything; null otherwise.
  Future<LocationResult?> lastKnown();

  /// Opens the phone's settings where [failure] is put right.
  Future<void> openSettings(LocationFailure failure);
}

/// [LocationSource] through the geolocator plugin.
class DeviceLocation implements LocationSource {
  const DeviceLocation();

  /// How long to wait for a first fix. The approximate permission uses the
  /// network, which can be slow to answer.
  static const _patience = Duration(seconds: 25);

  @override
  Future<LocationResult> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return const LocationResult.failed(LocationFailure.serviceOff);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(LocationFailure.deniedForever);
      }
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        return const LocationResult.failed(LocationFailure.denied);
      }
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: _patience),
        );
      } on TimeoutException {
        position = null;
      } on LocationServiceDisabledException {
        return const LocationResult.failed(LocationFailure.serviceOff);
      }
      // A town does not move: a position from earlier today is as good.
      position ??= await Geolocator.getLastKnownPosition();
      if (position == null) return const LocationResult.failed(LocationFailure.unavailable);
      return LocationResult.found(position.latitude, position.longitude);
    } on PermissionDeniedException {
      return const LocationResult.failed(LocationFailure.denied);
    } catch (_) {
      return const LocationResult.failed(LocationFailure.unavailable);
    }
  }

  @override
  Future<LocationResult?> lastKnown() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return null;
      final position = await Geolocator.getLastKnownPosition();
      return position == null ? null : LocationResult.found(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openSettings(LocationFailure failure) async {
    try {
      if (failure == LocationFailure.serviceOff) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {
      // No such screen on this phone: the message already says where to go.
    }
  }
}
