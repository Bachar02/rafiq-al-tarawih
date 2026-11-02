import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/recognition/models.dart';
import 'listen_state.dart';

/// What the screen tells the user, derived from session phase + tracker
/// status in one place, so every widget agrees.
enum DisplayStatus {
  idle,
  connecting,
  searching,
  following,
  uncertain,
  lost,
  reconnecting,
  stopping,
  paused,
  failed;

  static DisplayStatus of(ListenState s) => switch (s.phase) {
        SessionPhase.idle => DisplayStatus.idle,
        SessionPhase.connecting => DisplayStatus.connecting,
        SessionPhase.reconnecting => DisplayStatus.reconnecting,
        SessionPhase.stopping => DisplayStatus.stopping,
        SessionPhase.paused => DisplayStatus.paused,
        SessionPhase.failed => DisplayStatus.failed,
        SessionPhase.listening => s.track.position == null
            ? DisplayStatus.searching
            : switch (s.track.status) {
                TrackStatus.tracking => DisplayStatus.following,
                TrackStatus.uncertain => DisplayStatus.uncertain,
                TrackStatus.lost => DisplayStatus.lost,
                TrackStatus.idle => DisplayStatus.searching,
              },
      };

  String get label => switch (this) {
        DisplayStatus.idle => 'Ready',
        DisplayStatus.connecting => 'Connecting…',
        DisplayStatus.searching => 'Listening',
        DisplayStatus.following => 'Following',
        DisplayStatus.uncertain => 'Not sure',
        DisplayStatus.lost => "Can't hear clearly",
        DisplayStatus.reconnecting => 'Reconnecting…',
        DisplayStatus.stopping => 'Stopping…',
        DisplayStatus.paused => 'Paused',
        DisplayStatus.failed => 'Stopped',
      };

  Color color(BuildContext context) => switch (this) {
        DisplayStatus.following => context.colors.following,
        DisplayStatus.uncertain || DisplayStatus.reconnecting => context.colors.uncertain,
        DisplayStatus.lost || DisplayStatus.failed => context.colors.lost,
        DisplayStatus.searching || DisplayStatus.connecting => context.scheme.primary,
        _ => context.colors.muted,
      };

  /// The ayah on screen is the confirmed, current one (full contrast).
  bool get confident => this == DisplayStatus.following;
}
