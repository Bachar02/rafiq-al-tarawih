import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/theme.dart';
import '../../data/reading_stats.dart';

/// The first day of the week holding [day], for weeks that start on
/// [firstDayOfWeek] (0 = Sunday, as [MaterialLocalizations.firstDayOfWeekIndex]).
DateTime weekStart(DateTime day, int firstDayOfWeek) {
  final offset = (day.weekday % 7 - firstDayOfWeek) % 7;
  return DateTime(day.year, day.month, day.day - offset);
}

/// The first day shown by a grid of [weeks] columns ending with today's week.
DateTime gridStart(DateTime today, int weeks, int firstDayOfWeek) {
  final last = weekStart(today, firstDayOfWeek);
  return DateTime(last.year, last.month, last.day - 7 * (weeks - 1));
}

/// The chart's five shades, palest to darkest: the hairline for a day
/// without reading, then ink at rising strength, so it reads the same in
/// both themes. The first ink step is strong enough to tell from the
/// hairline in the dark theme too.
List<Color> readingShades(RafiqColors c) => [
      c.hairline,
      c.ink.withValues(alpha: 0.42),
      c.ink.withValues(alpha: 0.62),
      c.ink.withValues(alpha: 0.82),
      c.ink,
    ];

/// Days as squares, one column per week, today's week last (on the inline
/// end: the right, or the left in right-to-left layouts), each shaded by the
/// pages read that day ([readingLevel]). Today has a ring.
///
/// A picture to the screen reader: [semanticLabel] says what it shows, and
/// the screens put the same facts in words beside it.
class ReadingGrid extends StatelessWidget {
  const ReadingGrid({
    super.key,
    required this.stats,
    required this.weeks,
    required this.semanticLabel,
    this.cell = 12,
    this.gap = 3,
    this.months = false,
    this.selected,
    this.onDay,
  });

  final ReadingStats stats;
  final int weeks;
  final String semanticLabel;
  final double cell;
  final double gap;

  /// Month names above the columns where a month begins.
  final bool months;

  /// A day drawn with a ring (the one whose count is shown).
  final DateTime? selected;
  final ValueChanged<DateTime>? onDay;

  /// How many week columns fit in [width].
  static int weeksIn(double width, {double cell = 12, double gap = 3}) =>
      ((width + gap) / (cell + gap)).floor().clamp(1, 53);

  static const _monthRow = 18.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final firstDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final first = gridStart(stats.today, weeks, firstDay);
    final size = Size(weeks * (cell + gap) - gap, 7 * (cell + gap) - gap + (months ? _monthRow : 0));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final painter = _GridPainter(
      stats: stats,
      first: first,
      weeks: weeks,
      cell: cell,
      gap: gap,
      rtl: rtl,
      shades: readingShades(c),
      ring: c.ink,
      top: months ? _monthRow : 0,
      monthStyle: RubricText.caption.copyWith(color: c.inkSecondary, fontSize: 11, height: 1),
      locale: Localizations.localeOf(context).toLanguageTag(),
      selected: selected,
    );

    DateTime? dayAt(Offset p) {
      final x = rtl ? size.width - p.dx : p.dx;
      final y = p.dy - painter.top;
      if (x < 0 || y < 0) return null;
      final col = x ~/ (cell + gap), row = y ~/ (cell + gap);
      if (col >= weeks || row >= 7) return null;
      final day = DateTime(first.year, first.month, first.day + col * 7 + row);
      return day.isAfter(stats.today) ? null : day;
    }

    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onDay == null
              ? null
              : (d) {
                  final day = dayAt(d.localPosition);
                  if (day != null) onDay!(day);
                },
          child: CustomPaint(size: size, painter: painter),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.stats,
    required this.first,
    required this.weeks,
    required this.cell,
    required this.gap,
    required this.rtl,
    required this.shades,
    required this.ring,
    required this.top,
    required this.monthStyle,
    required this.locale,
    required this.selected,
  });

  final ReadingStats stats;
  final DateTime first;
  final int weeks;
  final double cell;
  final double gap;
  final bool rtl;
  final List<Color> shades;
  final Color ring;
  final double top;
  final TextStyle monthStyle;
  final String locale;
  final DateTime? selected;

  double _x(Size size, int col) {
    final x = col * (cell + gap);
    return rtl ? size.width - x - cell : x;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ring;
    final radius = Radius.circular(cell / 4);
    for (var col = 0; col < weeks; col++) {
      for (var row = 0; row < 7; row++) {
        final day = DateTime(first.year, first.month, first.day + col * 7 + row);
        if (day.isAfter(stats.today)) break;
        final rect = Rect.fromLTWH(_x(size, col), top + row * (cell + gap), cell, cell);
        fill.color = shades[readingLevel(stats.pagesOn(day))];
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);
        if (day == stats.today || day == selected) {
          canvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(1.5), radius), outline);
        }
        if (top > 0 && day.day == 1) _month(canvas, size, col, day);
      }
    }
  }

  void _month(Canvas canvas, Size size, int col, DateTime day) {
    if (weeks - col < 2) return; // no room for the name at the end
    final text = TextPainter(
      text: TextSpan(text: DateFormat.MMM(locale).format(day), style: monthStyle),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    final x = rtl ? _x(size, col) + cell - text.width : _x(size, col);
    text.paint(canvas, Offset(x, 0));
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.stats != stats ||
      old.first != first ||
      old.weeks != weeks ||
      old.rtl != rtl ||
      old.shades != shades ||
      old.selected != selected ||
      old.locale != locale;
}
