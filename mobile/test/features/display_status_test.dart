import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/features/listen/display_status.dart';
import 'package:rafiq/features/listen/listen_state.dart';

import '../support/fakes.dart';
import 'package:rafiq/l10n/l10n.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  final t0 = DateTime(2026, 3, 1, 21);
  DateTime after(int seconds) => t0.add(Duration(seconds: seconds));

  /// A listening session that started at t0, confirmed 93:3 at [confirmed]s
  /// and last heard sound at [sound]s.
  ListenState listening({
    TrackState? track,
    int? confirmed = 0,
    int? sound = 0,
    Position? anchor,
    Position? lastSure,
  }) =>
      ListenState(
        phase: SessionPhase.listening,
        track: track ?? at(93, 3),
        startedAt: t0,
        confirmedAt: confirmed == null ? null : after(confirmed),
        lastSoundAt: sound == null ? null : after(sound),
        anchor: anchor,
        lastSure: lastSure,
      );

  group('DisplayStatus.of', () {
    test('freshly confirmed tracking is Following, with a filled marker', () {
      final s = DisplayStatus.of(listening(), after(3));
      expect(s, DisplayStatus.following);
      expect(s.marker(held: true), MarkerFill.filled);
      expect(s.engineUnsure, isFalse);
    });

    test('no position yet: Listening, no marker', () {
      final s = DisplayStatus.of(listening(track: TrackState.empty), after(30));
      expect(s, DisplayStatus.listening);
      expect(s.marker(held: false), MarkerFill.none);
    });

    test('a pending guess alone is not a position', () {
      final track = TrackState(status: TrackStatus.uncertain, pending: pos(7, 29));
      expect(DisplayStatus.of(listening(track: track), after(1)), DisplayStatus.listening);
    });

    test('sound but no confirmed update for 10 s: No new match yet', () {
      final s = DisplayStatus.of(listening(confirmed: 0, sound: 11), after(11));
      expect(s, DisplayStatus.noNewMatch);
      expect(s.marker(held: true), MarkerFill.hollow);
      expect(s.engineUnsure, isFalse); // the numeral stays in ink
      expect(s.caption(en, 3), contains('Still showing ayah 3'));
    });

    test('quiet for 10 s: Little sound', () {
      final s = DisplayStatus.of(listening(confirmed: 0, sound: 0), after(11));
      expect(s, DisplayStatus.littleSound);
      expect(s.marker(held: true), MarkerFill.hollow);
      expect(s.caption(en, 3), contains('the last confirmed ayah'));
    });

    test('just under the window: still Following', () {
      expect(DisplayStatus.of(listening(confirmed: 0, sound: 0), after(9)), DisplayStatus.following);
    });

    test('engine states outrank the inferred ones', () {
      final quietAndStale = after(30);
      final lost = listening(track: at(93, 3, status: TrackStatus.lost), confirmed: 0, sound: 0);
      final unsure = listening(track: at(93, 3, status: TrackStatus.uncertain), confirmed: 0, sound: 0);
      expect(DisplayStatus.of(lost, quietAndStale), DisplayStatus.notMatching);
      expect(DisplayStatus.of(unsure, quietAndStale), DisplayStatus.notSure);
      expect(DisplayStatus.notMatching.engineUnsure, isTrue);
      expect(DisplayStatus.notSure.marker(held: true), MarkerFill.hollow);
    });

    test('session phase outranks everything', () {
      final failed = ListenState(phase: SessionPhase.failed, track: at(93, 3), error: ListenError.server);
      final paused = ListenState(phase: SessionPhase.paused, track: at(93, 3));
      expect(DisplayStatus.of(failed, t0), DisplayStatus.failed);
      expect(DisplayStatus.of(paused, t0), DisplayStatus.paused);
      expect(DisplayStatus.failed.marker(held: true), MarkerFill.none); // the Notice speaks
      expect(DisplayStatus.paused.label(en), isEmpty);
    });

    test('Al-Fatiha inside another surah: its own state, filled marker', () {
      final s = DisplayStatus.of(listening(track: at(1, 2), anchor: pos(93, 3)), after(2));
      expect(s, DisplayStatus.fatiha);
      expect(s.marker(held: true), MarkerFill.filled);
    });

    test('a position carried from an earlier session waits for confirmation', () {
      final s = DisplayStatus.of(listening(confirmed: null, sound: 0), after(2));
      expect(s, DisplayStatus.listening);
      expect(s.marker(held: true), MarkerFill.hollow);
    });

    test('idle: Ready without a position, Not following with one', () {
      expect(DisplayStatus.of(const ListenState(), t0), DisplayStatus.ready);
      expect(DisplayStatus.of(ListenState(track: at(93, 3)), t0), DisplayStatus.stopped);
      expect(DisplayStatus.stopped.marker(held: true), MarkerFill.hollow);
    });
  });

  test('no state ever claims anything about audio quality', () {
    for (final s in DisplayStatus.values) {
      final words = '${s.label(en)} ${s.caption(en, 3) ?? ''}'.toLowerCase();
      expect(words, isNot(contains("can't hear")));
      expect(words, isNot(contains('poor audio')));
      expect(words, isNot(contains('waiting for the imam')));
    }
  });
}
