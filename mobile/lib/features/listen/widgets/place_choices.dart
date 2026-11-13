import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/surah_names.dart';
import '../../../l10n/l10n.dart';
import '../place.dart';
import 'status_line.dart';

/// What the user can do about repeated words, under the status line (which
/// says what is happening): a few quiet buttons, never over the Quran text.
///
/// * [InSurah]: one button per ayah when there are at most
///   [maxAyahChoices] copies; otherwise one to choose the ayah in the text.
///   And "Stay on" the surah, unless the lock is already there.
/// * [AcrossSurahs]: one button per surah: its ayah, when it has only one
///   copy there; otherwise "Stay on" it (recognition then looks only there).
///
/// Every button goes through an existing action: an ayah opens the ayah sheet
/// ("The imam is here", confirmed there); a surah is the surah lock, with
/// Undo. Nothing here changes the position by itself. Nothing for [Placed]
/// or [Unplaced].
class PlaceChoices extends StatelessWidget {
  const PlaceChoices({
    super.key,
    required this.place,
    required this.names,
    required this.lock,
    required this.onAyah,
    required this.onStay,
    required this.onFindInText,
  });

  final Place place;
  final SurahNames names;

  /// The user's lock, if any: "Stay on" is not offered where it already is.
  final Hint? lock;

  /// The imam may be at this ayah: open its sheet.
  final ValueChanged<Position> onAyah;

  /// Stay on this surah (the surah lock).
  final ValueChanged<int> onStay;

  /// Open this surah's text at the first of its [copies], to tap the ayah.
  final void Function(int surah, List<Position> copies) onFindInText;

  /// More copies than this are a list, not a choice: the text is better.
  static const maxAyahChoices = 3;

  bool _lockedTo(int surah) => lock is SurahHint && (lock! as SurahHint).surah == surah;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final buttons = switch (place) {
      InSurah(:final surah, :final copies) => [
          if (copies.length <= maxAyahChoices)
            for (final p in copies) _Choice(label: l.semAyah(p.ayah), onTap: () => onAyah(p))
          else
            _Choice(
              icon: Icons.menu_book_outlined,
              label: l.chooseAyahInText,
              onTap: () => onFindInText(surah, copies),
            ),
          if (!_lockedTo(surah))
            _Choice(icon: Icons.lock_outline, label: l.stayOnSurah(names.of(surah)), onTap: () => onStay(surah)),
        ],
      AcrossSurahs(:final choices) => [
          for (final choice in choices)
            if (choice.only case final p?)
              _Choice(label: l.ayahSheetTitle(names.of(choice.surah), p.ayah), onTap: () => onAyah(p))
            else if (_lockedTo(choice.surah))
              _Choice(
                icon: Icons.menu_book_outlined,
                label: names.of(choice.surah),
                onTap: () => onFindInText(choice.surah, choice.copies),
              )
            else
              _Choice(
                icon: Icons.lock_outline,
                label: l.stayOnSurah(names.of(choice.surah)),
                onTap: () => onStay(choice.surah),
              ),
        ],
      Placed() || Unplaced() => const <Widget>[],
    };
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      // Under the status line's words, not its marker.
      padding: const EdgeInsetsDirectional.only(start: StatusLine.indent, top: RubricSpace.s3),
      child: Wrap(spacing: RubricSpace.s2, runSpacing: RubricSpace.s2, children: buttons),
    );
  }
}

/// One choice: the theme's outlined pill, 48px tall, compact across.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s4),
      textStyle: RubricText.label,
    );
    final text = Text(label, textAlign: TextAlign.center);
    return icon == null
        ? OutlinedButton(onPressed: onTap, style: style, child: text)
        : OutlinedButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 18), label: text);
  }
}
