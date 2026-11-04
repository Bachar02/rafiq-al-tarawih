import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';
import '../../../data/surah_names.dart';

/// The large ayah numeral opposite the surah name: what a worshipper reads in
/// one glance from a phone on a stand or a lap.
///
/// Shows only confirmed or held positions, never a pending guess. When the
/// engine is unsure the overline becomes LAST SURE and the numeral and surah
/// dim; the number itself never changes to an unconfirmed one. With no
/// position the numeral area shows an em dash. Mirrors in RTL layouts.
const _nbsp = ' ';

class PositionHeader extends StatelessWidget {
  const PositionHeader({
    super.key,
    required this.position,
    required this.quran,
    required this.names,
    this.unsure = false,
    this.onOpenSurahs,
  });

  final Position? position;
  final Quran quran;
  final SurahNames names;

  /// The engine itself is unsure (`uncertain`, `lost`).
  final bool unsure;

  /// Tapping the surah name opens the surah index.
  final VoidCallback? onOpenSurahs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = position;
    final surah = p == null ? null : quran.surah(p.surah);
    // The numeral is capped so the header never wraps; the meta line wraps.
    final numeralScaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

    final numeral = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text(
            unsure ? 'LAST SURE' : 'AYAH',
            style: RubricText.overline.copyWith(color: c.inkSecondary),
          ),
        ),
        // Newsreader's figures rise above the 60px line box.
        const SizedBox(height: RubricSpace.s2),
        AnimatedSwitcher(
          duration: RubricMotion.quick,
          child: Text(
            p == null ? '—' : '${p.ayah}',
            key: ValueKey(p?.ayah),
            textScaler: numeralScaler,
            maxLines: 1,
            style: RubricText.positionNumeral.copyWith(
              color: p == null || unsure ? c.inkSecondary : c.ink,
            ),
          ),
        ),
      ],
    );

    final title = surah == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Long names scale down rather than wrap.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  surah.nameAr,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  style: RubricText.surahAr.copyWith(color: unsure ? c.inkUpcoming : c.ink),
                ),
              ),
              Text(
                // Breaks only between the parts, never inside "Juz 30".
                '${names.of(surah.index)}$_nbsp· ${surah.index}$_nbsp· Juz$_nbsp${quran.juzOf(p!.verseId)}',
                textAlign: TextAlign.end,
                style: RubricText.label.copyWith(color: c.inkSecondary),
              ),
            ],
          );

    final tappable = surah != null && onOpenSurahs != null;
    return Semantics(
      container: true,
      button: tappable,
      label: p == null ? 'No position yet' : 'Surah ${names.of(p.surah)}, ayah ${p.ayah}${unsure ? ', not sure' : ''}',
      onTapHint: tappable ? 'open the surah list' : null,
      onTap: tappable ? onOpenSurahs : null,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            numeral,
            const SizedBox(width: RubricSpace.s4),
            Expanded(
              child: !tappable
                  ? Align(alignment: AlignmentDirectional.bottomEnd, child: title)
                  : Tooltip(
                      message: 'Surahs',
                      child: InkWell(
                        onTap: onOpenSurahs,
                        borderRadius: BorderRadius.circular(RubricRadius.sm),
                        child: Align(alignment: AlignmentDirectional.bottomEnd, child: title),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
