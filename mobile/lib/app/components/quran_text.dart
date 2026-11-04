import 'package:flutter/material.dart';

import '../../core/text/quran_display.dart';
import '../../data/quran.dart';
import '../theme.dart';

/// Where an ayah stands relative to the imam: luminance, not boxes, shows it.
/// Outside Taraweeh mode every ayah is [reading].
enum AyahTone {
  /// The reader: full `ink`, no imam, nothing animates.
  reading,

  /// Already recited: resting (`ink-recited`).
  recited,

  /// The imam's current ayah: brightest (`ink`), with the cinnabar margin rule.
  current,

  /// Not yet recited, or no position: readable (`ink-upcoming`).
  upcoming,
}

/// Justify only when the column is wide enough for its font size: narrower
/// lines open wide word gaps (measured over the whole Quran). At 26px this
/// justifies from a 300px column up.
bool justifyQuran({required double columnWidth, required double fontSize}) => columnWidth / fontSize >= 11.5;

/// One ayah as one block: its text, joined by a no-break space to its
/// enclosed end marker ۝ with Arabic-Indic digits.
///
/// Blocks stack with no gap, card, border or background: the even 2.2 line
/// rhythm carries the column so it reads as one text. The current ayah gets a
/// 2px `rubric` rule on its inline-start edge (the right, in RTL), 12px from
/// the text, and its end marker in `rubric`. When the engine is not sure the
/// rule turns dashed and the text drops to `ink-upcoming`; the position does
/// not move. Tone changes crossfade in [RubricMotion.settle]; text never moves.
class AyahBlock extends StatelessWidget {
  const AyahBlock({
    super.key,
    required this.verse,
    required this.tone,
    this.unsure = false,
    this.fontSize = 26,
    this.justify = true,
    this.highlighted = false,
    this.onTap,
    this.onLongPress,
  });

  final Verse verse;
  final AyahTone tone;

  /// Only meaningful for [AyahTone.current]: the engine is unsure.
  final bool unsure;

  /// `quran-body` × the user's text size.
  final double fontSize;
  final bool justify;

  /// The reader's [RafiqColors.mark] wash: the ayah a sheet acts on, or the
  /// one a search or bookmark just opened.
  final bool highlighted;

  /// Opens the ayah's actions (in Taraweeh mode: "The imam is here", a
  /// deliberate two-step correction).
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static const ruleWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = tone == AyahTone.current;
    final textColor = switch (tone) {
      AyahTone.reading => c.ink,
      AyahTone.recited => c.inkRecited,
      AyahTone.current => unsure ? c.inkUpcoming : c.ink,
      AyahTone.upcoming => c.inkUpcoming,
    };
    final markerColor = current ? c.rubric : textColor;

    Widget text(Color text, Color marker) => Text.rich(
          TextSpan(
            text: displayAyahText(verse.uthmani),
            children: [TextSpan(text: ayahEndMarker(verse.ayah), style: TextStyle(color: marker))],
          ),
          textAlign: justify ? TextAlign.justify : TextAlign.start,
          // The app's own text-size setting (0.85–1.6, validated with
          // this font) sizes the Quran, not the system font scale.
          textScaler: TextScaler.noScaling,
          style: RubricText.quranBody.copyWith(fontSize: fontSize, color: text),
        );

    // Reading tone never changes, so it skips the crossfade machinery: one
    // less pair of animation builders per ayah while scrolling on slow phones.
    final Widget body = tone == AyahTone.reading
        ? text(textColor, markerColor)
        : TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: textColor),
            duration: RubricMotion.settle,
            curve: RubricMotion.standard,
            builder: (context, t, _) => TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: markerColor),
              duration: RubricMotion.settle,
              curve: RubricMotion.standard,
              builder: (context, m, _) => text(t!, m!),
            ),
          );

    Widget block = Padding(
      padding: const EdgeInsets.symmetric(horizontal: RubricSpace.quranInline),
      child: body,
    );
    if (tone != AyahTone.reading) {
      block = Stack(
        children: [
          block,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: ruleWidth,
            child: AnimatedOpacity(
              opacity: current ? 1 : 0,
              duration: RubricMotion.settle,
              curve: RubricMotion.standard,
              child: CustomPaint(painter: _RulePainter(color: c.rubric, dashed: unsure)),
            ),
          ),
        ],
      );
    }
    if (highlighted) {
      block = DecoratedBox(
        decoration: BoxDecoration(color: c.mark, borderRadius: BorderRadius.circular(RubricRadius.sm)),
        child: block,
      );
    }

    final live = tone != AyahTone.reading;
    return Semantics(
      label: 'Ayah ${verse.ayah}${current ? ', the imam is here' : ''}',
      onTapHint: onTap == null ? null : (live ? 'mark where the imam is' : 'ayah actions'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Directionality(textDirection: TextDirection.rtl, child: block),
      ),
    );
  }
}

class _RulePainter extends CustomPainter {
  _RulePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (!dashed) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    const dash = 6.0, gap = 4.0;
    for (var y = 0.0; y < size.height; y += dash + gap) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, (size.height - y).clamp(0, dash)), paint);
    }
  }

  @override
  bool shouldRepaint(_RulePainter old) => old.color != color || old.dashed != dashed;
}

/// The surah's basmala, centred above ayah 1 (every surah except 1 and 9:
/// in Al-Fatiha it is ayah 1). Resting ink, like recited text.
class Basmala extends StatelessWidget {
  const Basmala({super.key, required this.text, this.scale = 1});

  final String text;

  /// The user's Quran text size.
  final double scale;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: RubricSpace.quranInline),
        child: Text(
          text,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          textScaler: TextScaler.noScaling,
          style: RubricText.quranBasmala.copyWith(
            fontSize: RubricText.quranBasmala.fontSize! * scale,
            color: context.colors.inkRecited,
          ),
        ),
      );
}

/// The basmala to show above [surah], or null (surahs 1 and 9).
String? basmalaFor(Quran quran, Surah surah) {
  if (!surah.hasBasmala) return null;
  return surah.basmalaUthmani.isEmpty ? quran.verse(1).uthmani : surah.basmalaUthmani;
}
