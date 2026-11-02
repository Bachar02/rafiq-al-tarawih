import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while listening (an interface so tests need no platform).
abstract interface class ScreenAwake {
  Future<void> enable();
  Future<void> disable();
}

class WakelockScreenAwake implements ScreenAwake {
  const WakelockScreenAwake();

  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Not fatal: the app still works, the screen may just dim.
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
