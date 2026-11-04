/// Rubric design tokens and themes. Source of truth: the Phase 3 handoff
/// `tokens/tokens.json`; rules: its brand book (docs/DESIGN.md §2.3).
///
/// Everything is ink on a dark page. One colour, [RafiqColors.rubric]
/// (cinnabar), has exactly one meaning: the imam's current Quranic position.
/// It never marks errors, the microphone, buttons or decoration; states that
/// need the user use [RafiqColors.signal] (lapis) with an icon and words.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// The Rubric palette. Elevation is lightness only: there are no shadows.
@immutable
class RafiqColors extends ThemeExtension<RafiqColors> {
  const RafiqColors({
    required this.ground,
    required this.surface,
    required this.surfaceRaised,
    required this.hairline,
    required this.ink,
    required this.inkSecondary,
    required this.inkUpcoming,
    required this.inkRecited,
    required this.rubric,
    required this.signal,
    required this.scrim,
  });

  /// The page behind the Quran and every screen.
  final Color ground;

  /// Settings rows, list groups, notices.
  final Color surface;

  /// Bottom sheets and dialogs. Nothing is ever brighter than this.
  final Color surfaceRaised;

  /// Dividers and secondary outlines. Decorative only, never the sole carrier of meaning.
  final Color hairline;

  /// Primary text and the current ayah.
  final Color ink;

  /// Labels, captions, icons, the in-product wordmark.
  final Color inkSecondary;

  /// Quran text not yet recited, and secondary surah titles.
  final Color inkUpcoming;

  /// Quran text already recited, and the basmala. Quran text at 22px+ only.
  final Color inkRecited;

  /// Cinnabar: the imam's current position. Nothing else.
  final Color rubric;

  /// Lapis: needs the user's action (always with an icon and words), focus rings.
  final Color signal;

  /// Behind sheets and dialogs. Darkens, never brightens.
  final Color scrim;

  /// Microphone level bars, lit. Deliberately neutral: the mic is never cinnabar.
  Color get levelOn => inkSecondary;

  /// Microphone level bars, unlit.
  Color get levelOff => hairline;

  static const dark = RafiqColors(
    ground: Color(0xFF100E0C),
    surface: Color(0xFF17140F),
    surfaceRaised: Color(0xFF1E1A15),
    hairline: Color(0xFF2C2721),
    ink: Color(0xFFE8E1D2),
    inkSecondary: Color(0xFF9C9384),
    inkUpcoming: Color(0xFF8C8477),
    inkRecited: Color(0xFF6B6358),
    rubric: Color(0xFFD9603F),
    signal: Color(0xFF93A9D6),
    scrim: Color(0xA0000000),
  );

  static const light = RafiqColors(
    ground: Color(0xFFF2ECE0),
    surface: Color(0xFFF8F4EC),
    surfaceRaised: Color(0xFFFFFFFF),
    hairline: Color(0xFFD9D0C0),
    ink: Color(0xFF1C1915),
    inkSecondary: Color(0xFF655E53),
    inkUpcoming: Color(0xFF5E574D),
    inkRecited: Color(0xFF8C8375),
    rubric: Color(0xFFB33E24),
    signal: Color(0xFF3D5A99),
    scrim: Color(0x521C1915),
  );

  @override
  RafiqColors copyWith({
    Color? ground,
    Color? surface,
    Color? surfaceRaised,
    Color? hairline,
    Color? ink,
    Color? inkSecondary,
    Color? inkUpcoming,
    Color? inkRecited,
    Color? rubric,
    Color? signal,
    Color? scrim,
  }) =>
      RafiqColors(
        ground: ground ?? this.ground,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        hairline: hairline ?? this.hairline,
        ink: ink ?? this.ink,
        inkSecondary: inkSecondary ?? this.inkSecondary,
        inkUpcoming: inkUpcoming ?? this.inkUpcoming,
        inkRecited: inkRecited ?? this.inkRecited,
        rubric: rubric ?? this.rubric,
        signal: signal ?? this.signal,
        scrim: scrim ?? this.scrim,
      );

  @override
  RafiqColors lerp(RafiqColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RafiqColors(
      ground: l(ground, other.ground),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      hairline: l(hairline, other.hairline),
      ink: l(ink, other.ink),
      inkSecondary: l(inkSecondary, other.inkSecondary),
      inkUpcoming: l(inkUpcoming, other.inkUpcoming),
      inkRecited: l(inkRecited, other.inkRecited),
      rubric: l(rubric, other.rubric),
      signal: l(signal, other.signal),
      scrim: l(scrim, other.scrim),
    );
  }
}

// -- type -------------------------------------------------------------------

/// The Book: Quran text and ayah-end markers. Never used for interface.
const quranFont = 'AmiriQuran';

/// The Title, Arabic: surah names.
const titleArFont = 'Amiri';

/// The Title, Latin: the ayah numeral, screen titles.
const titleFont = 'Newsreader';

/// The Interface: every label, status and setting.
const uiFont = 'IBMPlexSans';
const uiArFont = 'IBMPlexSansArabic';

/// Rubric type styles (colourless: callers add the colour token).
///
/// Newsreader and IBM Plex Sans are variable fonts. Flutter does not map
/// [FontWeight] onto a variable font's `wght` axis, so every style sets the
/// axis explicitly; use [RubricWeight.weighted] to change a weight.
abstract final class RubricText {
  /// IBM Plex Sans has no ʿ ʾ Ḥ ṣ (transliteration: Ḥafṣ ʿan ʿĀṣim, rakʿah,
  /// duʿāʾ). Amiri, already bundled, covers them: the last fallback, so they
  /// never fall to a missing glyph whatever the phone's system fonts.
  static const _uiFallback = [uiArFont, titleArFont];

  static TextStyle _ui(double size, double lineHeight, int weight, {double letterSpacing = 0}) => TextStyle(
        fontFamily: uiFont,
        fontFamilyFallback: _uiFallback,
        fontSize: size,
        height: lineHeight / size,
        letterSpacing: letterSpacing,
        fontWeight: _weight(weight),
        fontVariations: [FontVariation('wght', weight.toDouble())],
      );

  static TextStyle _uiAr(double size, double lineHeight, int weight) => TextStyle(
        fontFamily: uiArFont,
        fontFamilyFallback: const [uiFont, titleArFont],
        fontSize: size,
        height: lineHeight / size,
        fontWeight: _weight(weight),
      );

  static TextStyle _title(double size, double lineHeight, {double letterSpacing = 0}) => TextStyle(
        fontFamily: titleFont,
        fontSize: size,
        height: lineHeight / size,
        letterSpacing: letterSpacing,
        fontWeight: FontWeight.w500,
        // Optical size follows the point size, as browsers do automatically.
        fontVariations: [const FontVariation('wght', 500), FontVariation('opsz', size.clamp(6, 72).toDouble())],
        fontFeatures: const [FontFeature.liningFigures(), FontFeature.tabularFigures()],
      );

  /// The Quran column: 26px × the user's text size; the 2.2 ratio stays.
  static const quranBody = TextStyle(fontFamily: quranFont, fontSize: 26, height: 2.2);

  /// Centred above ayah 1 of every surah except 1 and 9.
  static const quranBasmala = TextStyle(fontFamily: quranFont, fontSize: 22, height: 2.0);

  /// The ayah number: the one thing read from across a prayer row.
  static final positionNumeral = _title(64, 60, letterSpacing: -0.64);

  /// Surah name on the main screen.
  static const surahAr = TextStyle(fontFamily: titleArFont, fontSize: 34, height: 44 / 34);

  /// Screen titles (Latin).
  static final titleLg = _title(28, 34);

  /// Sheet titles.
  static final sheetTitle = _ui(20, 28, 500);

  /// Primary control labels and the status line.
  static final labelLg = _ui(17, 24, 500);

  /// Secondary information, settings rows.
  static final label = _ui(15, 22, 400);

  /// State explanations, footnotes. Never smaller.
  static final caption = _ui(13, 18, 400);

  /// Latin only, uppercase. Arabic is never letter-spaced or capitalised.
  static final overline = _ui(12, 16, 500, letterSpacing: 12 * 0.14);

  /// Arabic interface: one line-height step taller than Latin, for the marks.
  static final labelLgAr = _uiAr(17, 28, 500);
  static final labelAr = _uiAr(15, 26, 400);
  static final captionAr = _uiAr(14, 24, 400);

  static FontWeight _weight(int w) => FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)];
}

extension RubricWeight on TextStyle {
  /// This style at [weight], on both static and variable fonts.
  TextStyle weighted(int weight) => copyWith(
        fontWeight: RubricText._weight(weight),
        fontVariations: [
          ...?fontVariations?.where((v) => v.axis != 'wght'),
          FontVariation('wght', weight.toDouble()),
        ],
      );
}

// -- spacing, radius, motion -------------------------------------------------

/// 4px base.
abstract final class RubricSpace {
  /// Inside the mic level indicator, icon to label.
  static const s1 = 4.0;

  /// Status marker to status text.
  static const s2 = 8.0;

  /// Current-ayah rule to text.
  static const s3 = 12.0;

  /// Between header blocks.
  static const s4 = 16.0;

  /// Screen side gutter on phones.
  static const s6 = 24.0;

  /// Between the position header and the Quran column.
  static const s8 = 32.0;

  /// Touch target minimum.
  static const s12 = 48.0;

  /// Primary listen control height on the ready screen.
  static const s16 = 64.0;

  static const gutter = s6;

  /// Quran column inline padding: marks overhang word edges by up to 0.5 em.
  static const quranInline = s3 + 2;

  /// Quran column top padding: high marks rise above the first line box.
  static const quranTop = s2;
}

abstract final class RubricRadius {
  static const sm = 4.0;
  static const md = 12.0;
  static const sheet = 24.0;
  static const pill = 28.0;
}

abstract final class RubricMotion {
  /// Press feedback, scrim fade, status text swap, marker fill.
  static const quick = Duration(milliseconds: 160);

  /// Current-ayah change: colour crossfade and the margin rule.
  static const settle = Duration(milliseconds: 320);

  /// Follow-scroll and Return-to-imam scroll.
  static const scroll = Duration(milliseconds: 600);

  /// Bottom sheet in; out is [sheetOut].
  static const sheet = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 200);

  /// Everything that moves into place.
  static const standard = Cubic(0.2, 0, 0, 1);

  /// Sheets and notices leaving.
  static const exit = Cubic(0.4, 0, 1, 1);

  /// Reduced motion: moves become crossfades of the same duration, scrolls jump.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

// -- themes -----------------------------------------------------------------

class AppTheme {
  /// The primary theme, designed first: Taraweeh is at night.
  static ThemeData dark() => _build(Brightness.dark, RafiqColors.dark);

  static ThemeData light() => _build(Brightness.light, RafiqColors.light);

  static ThemeData _build(Brightness brightness, RafiqColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.ink,
      onPrimary: c.ground,
      primaryContainer: c.surfaceRaised,
      onPrimaryContainer: c.ink,
      secondary: c.inkSecondary,
      onSecondary: c.ground,
      secondaryContainer: c.surface,
      onSecondaryContainer: c.ink,
      tertiary: c.signal,
      onTertiary: c.ground,
      // Errors are not alarming during prayer: lapis, never red.
      error: c.signal,
      onError: c.ground,
      surface: c.ground,
      onSurface: c.ink,
      surfaceContainerHighest: c.surface,
      onSurfaceVariant: c.inkSecondary,
      outline: c.hairline,
      outlineVariant: c.hairline,
      inverseSurface: c.ink,
      onInverseSurface: c.ground,
      inversePrimary: c.ground,
      shadow: Colors.transparent,
      scrim: c.scrim,
      surfaceTint: Colors.transparent,
    );

    TextStyle ink(TextStyle s) => s.copyWith(color: c.ink);
    final text = TextTheme(
      displayLarge: ink(RubricText.positionNumeral),
      headlineMedium: ink(RubricText.titleLg),
      headlineSmall: ink(RubricText.sheetTitle),
      titleLarge: ink(RubricText.titleLg),
      titleMedium: ink(RubricText.labelLg),
      titleSmall: ink(RubricText.label.weighted(500)),
      bodyLarge: ink(RubricText.label),
      bodyMedium: ink(RubricText.label),
      bodySmall: RubricText.caption.copyWith(color: c.inkSecondary),
      labelLarge: ink(RubricText.label.weighted(500)),
      labelMedium: RubricText.overline.copyWith(color: c.inkSecondary),
      labelSmall: RubricText.caption.copyWith(color: c.inkSecondary),
    );

    final radiusMd = BorderRadius.circular(RubricRadius.md);
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(RubricRadius.pill));
    WidgetStateProperty<Color?> pressed(Color? normal, Color? onPress) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? onPress : normal);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.ground,
      canvasColor: c.ground,
      extensions: [c],
      fontFamily: uiFont,
      textTheme: text,
      splashFactory: NoSplash.splashFactory,
      highlightColor: c.surfaceRaised.withValues(alpha: 0.6),
      hoverColor: c.surfaceRaised.withValues(alpha: 0.4),
      focusColor: c.signal.withValues(alpha: 0.16),
      dividerColor: c.hairline,
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.inkSecondary, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        foregroundColor: c.ink,
        iconTheme: IconThemeData(color: c.inkSecondary),
        actionsIconTheme: IconThemeData(color: c.inkSecondary),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: pressed(c.inkSecondary, c.ink),
          minimumSize: const WidgetStatePropertyAll(Size(RubricSpace.s12, RubricSpace.s12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.ground,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: c.inkSecondary,
          minimumSize: const Size(64, 56),
          shape: pill,
          textStyle: RubricText.labelLg,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          disabledForegroundColor: c.inkSecondary,
          side: BorderSide(color: c.hairline),
          minimumSize: const Size(64, RubricSpace.s12),
          shape: pill,
          textStyle: RubricText.label.weighted(500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(RubricSpace.s12, RubricSpace.s12),
          textStyle: RubricText.label.weighted(500),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkSecondary,
        textColor: c.ink,
        selectedColor: c.ink,
        selectedTileColor: c.surfaceRaised,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
        leadingAndTrailingTextStyle: text.bodyLarge?.copyWith(color: c.inkSecondary),
        minVerticalPadding: 12,
      ),
      switchTheme: SwitchThemeData(
        // Not cinnabar: a setting is not a position.
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.hairline),
        thumbColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ground : c.inkSecondary),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: const WidgetStatePropertyAll(null),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.ink,
        inactiveTrackColor: c.hairline,
        thumbColor: c.ink,
        overlayColor: c.ink.withValues(alpha: 0.08),
        activeTickMarkColor: c.ground.withValues(alpha: 0.5),
        inactiveTickMarkColor: c.inkSecondary.withValues(alpha: 0.5),
        valueIndicatorColor: c.surfaceRaised,
        valueIndicatorTextStyle: text.bodyMedium,
        trackHeight: 2,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.surface : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.ink : c.inkSecondary,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: c.hairline)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radiusMd)),
          textStyle: WidgetStatePropertyAll(RubricText.label.weighted(500)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        modalBackgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.hairline,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(RubricRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        isDense: true,
        // Material 3 adds the outline's gapPadding (4) on each side: 12 + 4 is the 16 dp inset.
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        hintStyle: text.bodyLarge?.copyWith(color: c.inkSecondary),
        labelStyle: text.bodyLarge?.copyWith(color: c.inkSecondary),
        floatingLabelStyle: text.bodySmall?.copyWith(color: c.inkSecondary),
        prefixIconColor: c.inkSecondary,
        errorStyle: text.bodySmall?.copyWith(color: c.signal),
        border: OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: c.hairline)),
        enabledBorder: OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: c.hairline)),
        focusedBorder: OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: c.signal, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: c.signal)),
        focusedErrorBorder:
            OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: c.signal, width: 2)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.ink,
        selectionColor: c.signal.withValues(alpha: 0.3),
        selectionHandleColor: c.signal,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.inkSecondary, linearTrackColor: c.hairline),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(RubricRadius.sm)),
        textStyle: text.bodySmall?.copyWith(color: c.ink),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceRaised,
        contentTextStyle: text.bodyMedium,
        actionTextColor: c.signal,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radiusMd, side: BorderSide(color: c.hairline)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // A plain fade-through: no zoom, never a flash of a lighter surface.
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension RafiqTheme on BuildContext {
  RafiqColors get colors => Theme.of(this).extension<RafiqColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get scheme => Theme.of(this).colorScheme;
}
