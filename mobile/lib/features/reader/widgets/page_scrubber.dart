import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/quran.dart';
import '../../../data/surah_names.dart';
import '../../../l10n/l10n.dart';

/// A handle on the screen's edge to fly through the Quran: drag it and a
/// bubble names the page, surah and juz under the finger; the reader follows
/// page by page. Shows while the text moves (and for a moment after), and
/// while dragged; otherwise it stays out of the text's way.
///
/// Positions are pages (1..604), so the handle means the same thing in the
/// scrolling text and in the page view.
class PageScrubber extends StatefulWidget {
  const PageScrubber({
    super.key,
    required this.quran,
    required this.names,
    required this.page,
    required this.activity,
    required this.onScrub,
  });

  final Quran quran;
  final SurahNames names;

  /// The page the reader shows now.
  final int page;

  /// Pinged when the text moves: the handle appears.
  final Listenable activity;

  /// The handle is over [page]: show it.
  final ValueChanged<int> onScrub;

  /// The touch area (the handle itself is narrower).
  static const width = 32.0;

  @override
  State<PageScrubber> createState() => _PageScrubberState();
}

class _PageScrubberState extends State<PageScrubber> {
  static const _handleHeight = 48.0;
  static const _linger = Duration(milliseconds: 1500);

  bool _shown = false;
  int? _dragPage;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.activity.addListener(_onActivity);
  }

  @override
  void didUpdateWidget(PageScrubber old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) {
      old.activity.removeListener(_onActivity);
      widget.activity.addListener(_onActivity);
    }
  }

  @override
  void dispose() {
    widget.activity.removeListener(_onActivity);
    _hide?.cancel();
    super.dispose();
  }

  void _onActivity() {
    if (!_shown) setState(() => _shown = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(_linger, () {
      if (mounted && _dragPage == null) setState(() => _shown = false);
    });
  }

  int _pageAt(double dy, double height) {
    final count = widget.quran.pages.count;
    final fraction = ((dy - _handleHeight / 2) / (height - _handleHeight)).clamp(0.0, 1.0);
    return (fraction * (count - 1)).round() + 1;
  }

  void _drag(double dy, double height) {
    final page = _pageAt(dy, height);
    if (page == _dragPage) return;
    setState(() => _dragPage = page);
    widget.onScrub(page);
  }

  void _end() {
    setState(() => _dragPage = null);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final page = _dragPage ?? widget.page;
    final count = widget.quran.pages.count;
    final dragging = _dragPage != null;
    final first = widget.quran.verse(widget.quran.pages.start(page));
    final where =
        '${l.pageNumber(page)} · ${widget.names.of(first.surah)} · ${l.juzNumber(widget.quran.juzOf(first.id))}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final top = (page - 1) / (count - 1) * (height - _handleHeight);
        return Semantics(
          slider: true,
          label: l.scrubberLabel,
          value: where,
          increasedValue: l.pageNumber((page + 10).clamp(1, count)),
          decreasedValue: l.pageNumber((page - 10).clamp(1, count)),
          onIncrease: () => widget.onScrub((page + 10).clamp(1, count)),
          onDecrease: () => widget.onScrub((page - 10).clamp(1, count)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The touch strip: only while shown, so the text's edge stays
              // tappable the rest of the time.
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                width: PageScrubber.width,
                child: IgnorePointer(
                  ignoring: !_shown && !dragging,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: (d) => _drag(d.localPosition.dy, height),
                    onVerticalDragUpdate: (d) => _drag(d.localPosition.dy, height),
                    onVerticalDragEnd: (_) => _end(),
                    onVerticalDragCancel: _end,
                  ),
                ),
              ),
              PositionedDirectional(
                end: RubricSpace.s1,
                top: top,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _shown || dragging ? 1 : 0,
                    duration: RubricMotion.quick,
                    child: Container(
                      width: dragging ? 8 : 6,
                      height: _handleHeight,
                      decoration: BoxDecoration(
                        color: dragging ? c.ink : c.inkSecondary,
                        borderRadius: BorderRadius.circular(RubricRadius.sm),
                      ),
                    ),
                  ),
                ),
              ),
              if (dragging)
                PositionedDirectional(
                  end: PageScrubber.width + RubricSpace.s1,
                  top: (top + _handleHeight / 2 - 22).clamp(0.0, height - 44),
                  child: IgnorePointer(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surfaceRaised,
                        border: Border.all(color: c.hairline),
                        borderRadius: BorderRadius.circular(RubricRadius.md),
                      ),
                      child: Text(where, style: RubricText.label.copyWith(color: c.ink)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
