import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'providers.dart';

/// The app's providers, which can be closed and opened again as a whole:
/// restoring a backup replaces everything stored, and every screen and
/// controller must then start again from it, as on a fresh launch.
class AppScope extends StatefulWidget {
  const AppScope({super.key, required this.overrides, required this.child});

  final List<Override> overrides;
  final Widget child;

  /// The scope above [context], if any.
  static AppScopeState? maybeOf(BuildContext context) => context.findAncestorStateOfType<AppScopeState>();

  @override
  State<AppScope> createState() => AppScopeState();
}

class AppScopeState extends State<AppScope> {
  int _generation = 0;
  bool _closed = false;

  /// Closes the app's state (each controller saves what it holds as it is
  /// disposed), runs [change] on what is stored, then opens the app again
  /// from there, told that a backup was restored ([restoredProvider]).
  Future<void> reopen(Future<void> Function() change) async {
    setState(() => _closed = true);
    // The old providers are disposed with this frame: their last saves are
    // made before [change], which therefore has the last word.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await change();
    } finally {
      if (mounted) {
        setState(() {
          _closed = false;
          _generation++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // A moment with nothing on screen but the window's own background.
    if (_closed) return const SizedBox.expand();
    return ProviderScope(
      key: ValueKey(_generation),
      overrides: [
        ...widget.overrides,
        if (_generation > 0) restoredProvider.overrideWithValue(true),
      ],
      child: widget.child,
    );
  }
}
