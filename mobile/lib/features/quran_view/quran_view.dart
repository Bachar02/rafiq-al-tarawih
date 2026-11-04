import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/components/quran_text.dart';
import '../../app/theme.dart';
import '../../core/recognition/models.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import 'book_index.dart';
import 'book_items.dart';

/// Commands for a [QuranView]: jumps, and the way back to the followed ayah.
///
/// Attach one by passing it to the view; calls before it is attached (or
/// after it is disposed) do nothing.
class QuranViewController {
  _QuranViewState? _view;

  bool get isAttached => _view != null;

  /// The verse at the top of the view (a surah header counts as its first
  /// ayah), once laid out.
  int? get topVerse => _view?._topVerse;

  /// Show [verseId] at the top (or at [alignment] of the view's height). Ayah
  /// 1 of a surah brings its header with it.
  void jumpToVerse(int verseId, {double alignment = 0}) {
    final view = _view;
    if (view == null) return;
    final verse = view.widget.quran.verse(verseId);
    view._jumpToIndex(
      verse.ayah == 1 ? view._book.ofSurah(verse.surah) : view._book.ofVerse(verseId),
      alignment: alignment,
    );
  }

  /// Open surah [surah] at its header.
  void jumpToSurah(int surah) => _view?._jumpToIndex(_view!._book.ofSurah(surah));

  /// Scroll back to [QuranView.followVerse] and follow it again.
  Future<void> returnToFollow() async => _view?._returnToFollow();
}

/// The Quran as one continuous, lazily built text: every surah's header and
/// ayahs, from 1:1 to 114:6. The reader and Taraweeh mode both show it, so
/// the two always look and scroll the same.
///
/// **Virtualized.** Only the ayahs on screen (plus a small cache) exist. The
/// list is anchored at an item with the two-sliver "center" technique: items
/// after the anchor grow down, items before it grow up. A jump anywhere is
/// a re-anchor, exact and constant-time, with no extent estimation and no
/// layout of the text in between.
///
/// **Reading** (`live: false`): every ayah in full ink; [onTopVerseChanged]
/// reports the ayah at the top, for the reading position.
///
/// **Taraweeh** (`live: true`): recited, current and coming ayahs by
/// luminance, the current one with the cinnabar rule. With [followVerse]
/// set, the view follows it: it scrolls only when the ayah leaves the
/// comfort zone (25–60% of the height) and brings it back to about 38%.
/// Scrolling by hand detaches following; once the followed ayah is out of
/// view [onAwayChanged] reports it, so the screen can offer the way back
/// ([QuranViewController.returnToFollow]). A hand scroll that ends with the
/// ayah in view re-attaches.
class QuranView extends StatefulWidget {
  const QuranView({
    super.key,
    required this.quran,
    required this.names,
    required this.initialVerse,
    this.controller,
    this.textScale = 1.0,
    this.live = false,
    this.current,
    this.unsure = false,
    this.followVerse,
    this.highlightedVerse,
    this.onAyahTap,
    this.onAyahLongPress,
    this.onTopVerseChanged,
    this.onAwayChanged,
    this.onUserScroll,
    this.horizontalPadding = RubricSpace.gutter,
    this.bottomPadding = 0,
  });

  final Quran quran;
  final SurahNames names;

  /// Where the view opens (ayah 1 opens at its surah's header). Ignored
  /// when [followVerse] is set: the view opens on that.
  final int initialVerse;
  final QuranViewController? controller;

  /// The user's Quran text size, 0.85–1.6.
  final double textScale;

  /// Taraweeh mode: tones relative to [current].
  final bool live;

  /// The imam's position, marked when [live].
  final Position? current;

  /// The engine is unsure: dashed rule, dimmer current ayah.
  final bool unsure;

  /// The verse to keep in view, or null to leave scrolling to the user.
  final int? followVerse;

  /// The reader's [RafiqColors.mark] wash on one ayah.
  final int? highlightedVerse;

  final ValueChanged<Verse>? onAyahTap;
  final ValueChanged<Verse>? onAyahLongPress;

  /// The verse at the top changed (scrolling or a jump).
  final ValueChanged<int>? onTopVerseChanged;

  /// The followed verse went out of view after a hand scroll (or came back).
  final ValueChanged<bool>? onAwayChanged;

  /// The user started or stopped dragging (for hiding floating controls).
  final ValueChanged<ScrollDirection>? onUserScroll;

  final double horizontalPadding;

  /// Room at the end for an overlay (a floating button or pill).
  final double bottomPadding;

  @override
  State<QuranView> createState() => _QuranViewState();
}

typedef _Geometry = ({double top, double height, double viewport});

class _QuranViewState extends State<QuranView> {
  static const _comfortTop = 0.25, _comfortBottom = 0.60, _followAt = 0.38;
  static const _centerKey = ValueKey('quran-view-center');

  late BookIndex _book;

  /// The item at scroll offset 0.
  late int _anchor;
  final _scroll = ScrollController(initialScrollOffset: -RubricSpace.quranTop);

  /// The items that are built now, by index: at most a screenful plus the cache.
  final _built = <int, BuildContext>{};

  /// Rebuilt only when what the items show changes, so a parent rebuild
  /// (the Taraweeh screen updates the mic level several times a second)
  /// does not rebuild a single ayah.
  SliverChildBuilderDelegate? _before, _after;
  bool _justify = true;

  int? _topVerse;
  int _topIndex = 0;
  bool _topUpdateScheduled = false;

  /// The user scrolled by hand: no auto-follow.
  bool _detached = false;

  /// Detached, and the followed ayah is out of view.
  bool _away = false;

  @override
  void initState() {
    super.initState();
    _book = BookIndex(widget.quran);
    final follow = widget.followVerse;
    _anchor = follow != null ? _book.ofVerse(follow) : _openingIndex(widget.initialVerse);
    widget.controller?._view = this;
    _afterLayout(() {
      if (widget.followVerse != null) _follow(animate: false, force: true);
      _updateTop();
    });
  }

  int _openingIndex(int verseId) {
    final v = widget.quran.verse(verseId);
    return v.ayah == 1 ? _book.ofSurah(v.surah) : _book.ofVerse(verseId);
  }

  @override
  void didUpdateWidget(QuranView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._view == this) old.controller!._view = null;
      widget.controller?._view = this;
    }
    if (old.quran != widget.quran) _book = BookIndex(widget.quran);
    final scaleChanged = old.textScale != widget.textScale;
    if (scaleChanged ||
        old.quran != widget.quran ||
        old.names != widget.names ||
        old.live != widget.live ||
        old.current?.verseId != widget.current?.verseId ||
        old.unsure != widget.unsure ||
        old.highlightedVerse != widget.highlightedVerse) {
      _invalidate();
    }

    if (widget.followVerse == null) {
      if (old.followVerse != null) {
        _detached = false;
        _afterLayout(() => _setAway(false));
      }
      // A new size moves the text under a still anchor: keep the top ayah.
      if (scaleChanged) {
        final top = _topIndex;
        _afterLayout(() => _jumpToIndex(top));
      }
    } else if (old.followVerse == null) {
      _detached = false;
      _afterLayout(() => _follow(force: true));
    } else if (old.followVerse != widget.followVerse || scaleChanged) {
      _afterLayout(() => _detached ? _setAway(!_followVisible()) : _follow(force: scaleChanged));
    }
  }

  @override
  void dispose() {
    if (widget.controller?._view == this) widget.controller!._view = null;
    _scroll.dispose();
    super.dispose();
  }

  void _invalidate() {
    _before = null;
    _after = null;
  }

  void _afterLayout(VoidCallback f) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  // -- geometry --------------------------------------------------------------

  /// Where built item [index] is, relative to the viewport. Null if it is
  /// not built (far from the screen).
  ///
  /// Measured in scroll space (the offset that would reveal the item, minus
  /// the current offset), not from paint positions: scroll notifications
  /// arrive before the next layout, and paint positions would be a frame
  /// stale exactly when a drag ends.
  _Geometry? _geometry(int index) {
    final context = _built[index];
    if (context == null || !context.mounted || !_scroll.hasClients) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    final position = _scroll.position;
    final reveal = viewport.getOffsetToReveal(box, 0).offset;
    return (top: reveal - position.pixels, height: box.size.height, viewport: position.viewportDimension);
  }

  void _scheduleTopUpdate() {
    if (_topUpdateScheduled) return;
    _topUpdateScheduled = true;
    _afterLayout(() {
      _topUpdateScheduled = false;
      _updateTop();
    });
  }

  /// The first built item that reaches below the top inset (an ayah
  /// showing only its last few pixels above the text is not "at the top").
  void _updateTop() {
    int? best;
    for (final index in _built.keys) {
      if (best != null && index >= best) continue;
      final g = _geometry(index);
      if (g != null && g.top + g.height > RubricSpace.quranTop + 1) best = index;
    }
    if (best == null) return;
    _topIndex = best;
    final verse = _book.verseAt(best);
    if (verse != _topVerse) {
      _topVerse = verse;
      widget.onTopVerseChanged?.call(verse);
    }
  }

  // -- scrolling -------------------------------------------------------------

  /// Put item [index] at [alignment] of the height: a scroll if it is
  /// built, otherwise a re-anchor.
  void _jumpToIndex(int index, {double alignment = 0}) {
    if (!mounted) return;
    final g = _geometry(index);
    if (g != null && _scroll.hasClients) {
      final p = _scroll.position;
      final to = p.pixels + g.top - g.viewport * alignment - RubricSpace.quranTop;
      _scroll.jumpTo(to.clamp(p.minScrollExtent, p.maxScrollExtent));
    } else {
      setState(() {
        _anchor = index;
        _invalidate();
      });
      if (_scroll.hasClients) _scroll.jumpTo(-RubricSpace.quranTop);
      if (alignment > 0) {
        _afterLayout(() {
          if (!_scroll.hasClients) return;
          final p = _scroll.position;
          final to = -p.viewportDimension * alignment - RubricSpace.quranTop;
          _scroll.jumpTo(to.clamp(p.minScrollExtent, p.maxScrollExtent));
        });
      }
    }
    _scheduleTopUpdate();
  }

  Future<void> _scrollToOffset(double target, {required bool animate}) async {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final to = target.clamp(p.minScrollExtent, p.maxScrollExtent);
    if (!animate || RubricMotion.reduced(context)) {
      _scroll.jumpTo(to);
    } else {
      await _scroll.animateTo(to, duration: RubricMotion.scroll, curve: RubricMotion.standard);
    }
  }

  /// Bring the followed ayah back into the comfort zone, if it left it. A
  /// far one (not built) is a cut, not a long scroll through the text.
  void _follow({bool animate = true, bool force = false}) {
    final verse = widget.followVerse;
    if (verse == null || !_scroll.hasClients) return;
    final index = _book.ofVerse(verse);
    final g = _geometry(index);
    if (g == null) {
      _jumpToIndex(index, alignment: _followAt);
      return;
    }
    final inComfort = g.top >= g.viewport * _comfortTop && g.top <= g.viewport * _comfortBottom;
    if (inComfort && !force) return;
    unawaited(_scrollToOffset(_scroll.offset + g.top - g.viewport * _followAt, animate: animate));
  }

  Future<void> _returnToFollow() async {
    final verse = widget.followVerse;
    if (verse != null) {
      final index = _book.ofVerse(verse);
      final g = _geometry(index);
      if (g == null) {
        _jumpToIndex(index, alignment: _followAt);
      } else {
        await _scrollToOffset(_scroll.offset + g.top - g.viewport * _followAt, animate: true);
      }
    }
    if (!mounted) return;
    _detached = false;
    _setAway(false);
  }

  /// Some of the followed ayah is on screen.
  bool _followVisible() {
    final verse = widget.followVerse;
    if (verse == null) return true;
    final g = _geometry(_book.ofVerse(verse));
    return g != null && g.top + g.height > 0 && g.top < g.viewport;
  }

  void _setAway(bool value) {
    if (_away == value) return;
    _away = value;
    widget.onAwayChanged?.call(value);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is UserScrollNotification) {
      if (n.direction != ScrollDirection.idle && widget.followVerse != null) _detached = true;
      widget.onUserScroll?.call(n.direction);
    }
    if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
      _scheduleTopUpdate();
      if (_detached) {
        final visible = _followVisible();
        _setAway(!visible);
        if (n is ScrollEndNotification && visible) _detached = false;
      }
    }
    return false;
  }

  // -- items -----------------------------------------------------------------

  SliverChildBuilderDelegate _delegate(int Function(int) indexOf, int count) => SliverChildBuilderDelegate(
        (context, i) => _item(indexOf(i)),
        childCount: count,
        // Nothing in an item has state worth keeping off screen.
        addAutomaticKeepAlives: false,
      );

  Widget _item(int index) {
    final item = _book.at(index);
    final Widget child = switch (item) {
      SurahHeaderItem(:final surah) => _withMark(
          surah.firstVerseId,
          SurahHeader(quran: widget.quran, surah: surah, names: widget.names, scale: widget.textScale),
        ),
      AyahItem(:final verse) => verse.ayah == 1 ? _ayah(verse) : _withMark(verse.id, _ayah(verse)),
    };
    return _Tracked(index: index, registry: _built, child: child);
  }

  Widget _withMark(int verseId, Widget child) {
    final label = DivisionMark.labelFor(widget.quran, verseId);
    if (label == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [DivisionMark(label: label), child],
    );
  }

  Widget _ayah(Verse verse) => AyahBlock(
        verse: verse,
        tone: _toneOf(verse),
        unsure: widget.unsure,
        fontSize: RubricText.quranBody.fontSize! * widget.textScale,
        justify: _justify,
        highlighted: verse.id == widget.highlightedVerse,
        // Read at tap time: a parent's new closure must not rebuild the text.
        onTap: () => widget.onAyahTap?.call(verse),
        onLongPress: widget.onAyahLongPress == null ? null : () => widget.onAyahLongPress?.call(verse),
      );

  AyahTone _toneOf(Verse verse) {
    if (!widget.live) return AyahTone.reading;
    final current = widget.current;
    if (current == null || current.surah != verse.surah || verse.ayah > current.ayah) return AyahTone.upcoming;
    return verse.ayah == current.ayah ? AyahTone.current : AyahTone.recited;
  }

  @override
  Widget build(BuildContext context) {
    final ground = context.colors.ground;
    return LayoutBuilder(
      builder: (context, constraints) {
        final column = constraints.maxWidth - 2 * widget.horizontalPadding;
        final justify = justifyQuran(columnWidth: column, fontSize: RubricText.quranBody.fontSize! * widget.textScale);
        if (justify != _justify) {
          _justify = justify;
          _invalidate();
        }
        final anchor = _anchor;
        _before ??= _delegate((i) => anchor - 1 - i, anchor);
        _after ??= _delegate((i) => anchor + i, _book.length - anchor);
        final inline = EdgeInsets.symmetric(horizontal: widget.horizontalPadding);
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SizedBox.expand(
                child: CustomScrollView(
                  controller: _scroll,
                  center: _centerKey,
                  slivers: [
                    // High marks rise above the first line box: never clip there.
                    const SliverToBoxAdapter(child: SizedBox(height: RubricSpace.quranTop)),
                    SliverPadding(padding: inline, sliver: SliverList(delegate: _before!)),
                    SliverPadding(key: _centerKey, padding: inline, sliver: SliverList(delegate: _after!)),
                    SliverToBoxAdapter(child: SizedBox(height: 40 + widget.bottomPadding)),
                  ],
                ),
              ),
            ),
            // A 40px fade to the page at the bottom edge.
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

/// Registers its element while built, so the view can find where an item
/// is without a GlobalKey per ayah.
class _Tracked extends StatefulWidget {
  const _Tracked({required this.index, required this.registry, required this.child});

  final int index;
  final Map<int, BuildContext> registry;
  final Widget child;

  @override
  State<_Tracked> createState() => _TrackedState();
}

class _TrackedState extends State<_Tracked> {
  @override
  void initState() {
    super.initState();
    widget.registry[widget.index] = context;
  }

  @override
  void didUpdateWidget(_Tracked old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index || old.registry != widget.registry) {
      if (old.registry[old.index] == context) old.registry.remove(old.index);
      widget.registry[widget.index] = context;
    }
  }

  @override
  void dispose() {
    if (widget.registry[widget.index] == context) widget.registry.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
