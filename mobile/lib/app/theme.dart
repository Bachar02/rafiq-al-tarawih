/// Design tokens and themes. See docs/DESIGN.md §2.3.
///
/// Dark is the default: Taraweeh is at night, often in dim mosques. Status
/// colors carry meaning (following / not sure / lost) and are never used
/// decoratively.
library;

import 'package:flutter/material.dart';

/// Colors the Material scheme has no slot for.
@immutable
class RafiqColors extends ThemeExtension<RafiqColors> {
  const RafiqColors({
    required this.following,
    required this.uncertain,
    required this.lost,
    required this.gold,
    required this.muted,
    required this.highlight,
    required this.surfaceRaised,
    required this.paper,
    required this.recited,
  });

  /// Status: confidently following the imam.
  final Color following;

  /// Status: showing the last good ayah, not sure.
  final Color uncertain;

  /// Status: cannot hear clearly / connection problems.
  final Color lost;

  /// Ayah number markers.
  final Color gold;

  /// Secondary text.
  final Color muted;

  /// Background of the ayah being recited.
  final Color highlight;

  /// Cards on top of the page background.
  final Color surfaceRaised;

  /// The mushaf page.
  final Color paper;

  /// Ayahs the imam has already recited (gently dimmed text).
  final Color recited;

  static const dark = RafiqColors(
    following: Color(0xFF4ADE80),
    uncertain: Color(0xFFFBBF24),
    lost: Color(0xFFF87171),
    gold: Color(0xFFD4B483),
    muted: Color(0xFF93A39B),
    highlight: Color(0xFF1B4A44),
    surfaceRaised: Color(0xFF18201D),
    paper: Color(0xFF141B18),
    recited: Color(0xFF7F8C86),
  );

  static const light = RafiqColors(
    following: Color(0xFF15803D),
    uncertain: Color(0xFFB45309),
    lost: Color(0xFFB91C1C),
    gold: Color(0xFF9A7440),
    muted: Color(0xFF66706A),
    highlight: Color(0xFFCDEBE5),
    surfaceRaised: Color(0xFFFFFFFF),
    paper: Color(0xFFFBF7EC),
    recited: Color(0xFF8A8F86),
  );

  @override
  RafiqColors copyWith({
    Color? following,
    Color? uncertain,
    Color? lost,
    Color? gold,
    Color? muted,
    Color? highlight,
    Color? surfaceRaised,
    Color? paper,
    Color? recited,
  }) =>
      RafiqColors(
        following: following ?? this.following,
        uncertain: uncertain ?? this.uncertain,
        lost: lost ?? this.lost,
        gold: gold ?? this.gold,
        muted: muted ?? this.muted,
        highlight: highlight ?? this.highlight,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        paper: paper ?? this.paper,
        recited: recited ?? this.recited,
      );

  @override
  RafiqColors lerp(RafiqColors? other, double t) {
    if (other == null) return this;
    return RafiqColors(
      following: Color.lerp(following, other.following, t)!,
      uncertain: Color.lerp(uncertain, other.uncertain, t)!,
      lost: Color.lerp(lost, other.lost, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      recited: Color.lerp(recited, other.recited, t)!,
    );
  }
}

/// Font family for Quranic text and surah names (bundled, OFL).
const quranFont = 'AmiriQuran';

class AppTheme {
  static const _primaryDark = Color(0xFF2DD4BF);
  static const _primaryLight = Color(0xFF0F766E);

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        primary: _primaryDark,
        background: const Color(0xFF0E1412),
        surface: const Color(0xFF151C19),
        onSurface: const Color(0xFFE8EEEA),
        extra: RafiqColors.dark,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        primary: _primaryLight,
        background: const Color(0xFFF6F4EE),
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF1C2420),
        extra: RafiqColors.light,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color onSurface,
    required RafiqColors extra,
  }) {
    final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
      primary: primary,
      onPrimary: brightness == Brightness.dark ? const Color(0xFF042F2B) : Colors.white,
      surface: surface,
      onSurface: onSurface,
      background: background,
      onBackground: onSurface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      extensions: [extra],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        color: extra.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

extension RafiqTheme on BuildContext {
  RafiqColors get colors => Theme.of(this).extension<RafiqColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get scheme => Theme.of(this).colorScheme;
}
