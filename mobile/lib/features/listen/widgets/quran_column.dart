import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/components/quran_text.dart';
import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';
import '../../../data/surah_names.dart';

/// The hero of the screen: one surah as a column of [AyahBlock]s, the imam's
/// current ayah marked by luminance and a single cinnabar margin rule.
///
/// Follow-scroll moves the text only when the current ayah leaves the comfort
/// zone (25–60% of the column height), bringing it back to about 38%; it does
/// not creep every ayah. Scrolling by hand detaches following: the column
/// stops auto-scrolling and, once the current ayah is out of view, reports it
/// through [onAwayChanged] so the screen can offer "Back to the imam"
/// ([QuranColumnState.returnToImam]). A hand scroll that ends with the ayah
/// in view re-attaches. Recognition continues underneath either way.
class QuranColumn extends StatefulWidget {
  const QuranColumn({
    super.key,
    required this.quran,
    required this.names,
    required this.surah,
    required this.current,
    required this.onAyahTap,
    required this.onOpenSurah,
    this.unsure = false,
    this.showTitle = false,
    this.textScale = 1.0,
    this.onAwayChanged,
    this.bottomPadding = 0,
  });

  final Quran quran;
  final SurahNames names;
  final int surah;

  /// The imam's position (marked if it is in this surah).
  final Position? current;

  /// The engine is unsure: dashed rule, dimmer current ayah.
  final bool unsure;

  /// Show this surah's name at the top: the header names another surah
  /// (browsing) or none yet.
  final bool showTitle;
  final ValueChanged<Verse> onAyahTap;
  final ValueChanged<int> onOpenSurah;
  final double textScale;

  /// The user scrolled the current ayah out of view (or back).
  final ValueChanged<bool>? onAwayChanged;

  /// Room at the end for an overlay (the Return-to-imam pill).
  final double bottomPadding;

  @override
  State<QuranColumn> createState() => QuranColumnState();
}

class QuranColumnState extends State<QuranColumn> {
  static const _comfortTop = 0.25, _comfortBottom = 0.60, _anchor = 0.38;

  final _scroll = ScrollController();
  var _keys = <int, GlobalKey>{}; // by ayah
  /// The user scrolled by hand: no auto-follow.
  bool _detached = false;

  /// Detached, and the current ayah is out of view.
  bool _away = false;

  Position? get _currentHere => widget.current?.surah == widget.surah ? widget.current : null;

  @override
  void initState() {
    super.initState();
    _keys = _makeKeys();
    _afterLayout(() => _follow(animate: false, force: true));
  }

  @override
  void didUpdateWidget(QuranColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surah != widget.surah) {
      _keys = _makeKeys();
      _detached = false;
      // Not here: the parent cannot rebuild during this build, and scrolling
      // notifies listeners. After the frame.
      _afterLayout(() {
        _setAway(false);
        if (_scroll.hasClients) _scroll.jumpTo(0);
        _follow(animate: false, force: true);
      });
    } else if (widget.current != oldWidget.current || widget.textScale != oldWidget.textScale) {
      _afterLayout(() => _detached ? _setAway(!_currentVisible()) : _follow());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Map<int, GlobalKey> _makeKeys() => {for (final v in widget.quran.surahVerses(widget.surah)) v.ayah: GlobalKey()};

  void _afterLayout(VoidCallback f) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  /// Where the current ayah's block starts: its scroll offset and its top
  /// within the viewport. Null if it is not laid out in this surah.
  ({double offset, double top, double height, double viewport})? _currentGeometry() {
    final current = _currentHere;
    if (current == null || !_scroll.hasClients) return null;
    final box = _keys[current.ayah]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    final offset = viewport.getOffsetToReveal(box, 0).offset;
    return (
      offset: offset,
      top: offset - _scroll.offset,
      height: box.size.height,
      viewport: _scroll.position.viewportDimension,
    );
  }

  /// Bring the current ayah back into the comfort zone, if it left it.
  void _follow({bool animate = true, bool force = false}) {
    final g = _currentGeometry();
    if (g == null) return;
    final inComfort = g.top >= g.viewport * _comfortTop && g.top <= g.viewport * _comfortBottom;
    if (inComfort && !force) return;
    _scrollTo(g.offset - g.viewport * _anchor, animate: animate);
  }

  Future<void> _scrollTo(double target, {required bool animate}) async {
    final position = _scroll.position;
    final to = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (!animate || RubricMotion.reduced(context)) {
      _scroll.jumpTo(to);
    } else {
      await _scroll.animateTo(to, duration: RubricMotion.scroll, curve: RubricMotion.standard);
    }
  }

  /// Back to the imam: one scroll to the position, then re-attach (the
  /// screen fades the pill out).
  Future<void> returnToImam() async {
    final g = _currentGeometry();
    if (g != null) await _scrollTo(g.offset - g.viewport * _anchor, animate: true);
    if (!mounted) return;
    _detached = false;
    _setAway(false);
  }

  void _setAway(bool value) {
    if (_away == value) return;
    _away = value;
    widget.onAwayChanged?.call(value);
  }

  /// Some of the current ayah is on screen (true when it is not in this surah:
  /// the screen handles browsing).
  bool _currentVisible() {
    final g = _currentGeometry();
    if (g == null) return true;
    return g.top + g.height > 0 && g.top < g.viewport;
  }

  bool _onScroll(ScrollNotification n) {
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle && _currentHere != null) {
      _detached = true;
    }
    if (_detached && (n is ScrollUpdateNotification || n is ScrollEndNotification)) {
      final visible = _currentVisible();
      _setAway(!visible);
      if (n is ScrollEndNotification && visible) _detached = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final quran = widget.quran;
    final surah = quran.surah(widget.surah);
    final verses = quran.surahVerses(widget.surah);
    final fontSize = RubricText.quranBody.fontSize! * widget.textScale;
    final current = _currentHere;
    final basmala = basmalaFor(quran, surah);
    final ground = context.colors.ground;

    return LayoutBuilder(
      builder: (context, constraints) {
        final justify = justifyQuran(columnWidth: constraints.maxWidth, fontSize: fontSize);
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                controller: _scroll,
                // High marks rise above the first line box: never clip there.
                padding: EdgeInsets.only(top: RubricSpace.quranTop, bottom: 40 + widget.bottomPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.showTitle) _SurahTitle(surah: surah, names: widget.names),
                    if (basmala != null) Basmala(text: basmala, scale: widget.textScale),
                    for (final v in verses)
                      AyahBlock(
                        key: _keys[v.ayah],
                        verse: v,
                        tone: current == null || v.ayah > current.ayah
                            ? AyahTone.upcoming
                            : v.ayah == current.ayah
                                ? AyahTone.current
                                : AyahTone.recited,
                        unsure: widget.unsure,
                        fontSize: fontSize,
                        justify: justify,
                        onTap: () => widget.onAyahTap(v),
                      ),
                    const SizedBox(height: RubricSpace.s6),
                    _SurahNav(quran: quran, names: widget.names, surah: widget.surah, onOpen: widget.onOpenSurah),
                  ],
                ),
              ),
            ),
            // A 40px fade to the page at the column's bottom edge.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 40,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [ground.withValues(alpha: 0), ground],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The surah's name at the top of the column, when the header shows another.
class _SurahTitle extends StatelessWidget {
  const _SurahTitle({required this.surah, required this.names});

  final Surah surah;
  final SurahNames names;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: RubricSpace.s4),
      child: Column(
        children: [
          Text(
            surah.nameAr,
            textDirection: TextDirection.rtl,
            style: RubricText.surahAr.copyWith(fontSize: 28, color: c.inkUpcoming),
          ),
          Text(
            '${names.of(surah.index)} · ${surah.index} · ${surah.ayahCount} ayahs',
            textAlign: TextAlign.center,
            style: RubricText.caption.copyWith(color: c.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Previous and next surah, at the end of the column. Reading order is right
/// to left: the next surah is on the left.
class _SurahNav extends StatelessWidget {
  const _SurahNav({required this.quran, required this.names, required this.surah, required this.onOpen});

  final Quran quran;
  final SurahNames names;
  final int surah;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(foregroundColor: context.colors.inkSecondary);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          if (surah > 1)
            Flexible(
              child: TextButton.icon(
                style: style,
                onPressed: () => onOpen(surah - 1),
                icon: const Icon(Icons.chevron_right, size: 20),
                label: Text(names.of(surah - 1), overflow: TextOverflow.ellipsis),
              ),
            ),
          const Spacer(),
          if (surah < quran.surahs.length)
            Flexible(
              child: TextButton(
                style: style,
                onPressed: () => onOpen(surah + 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(names.of(surah + 1), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: RubricSpace.s1),
                    const Icon(Icons.chevron_left, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
