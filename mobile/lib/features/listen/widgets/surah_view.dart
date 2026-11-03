import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';

/// The surah being recited, with the current ayah highlighted and followed.
///
/// Auto-follow keeps the current ayah about a third of the way down. If the
/// user scrolls by hand, following pauses for [manualHold] and a "Back to the
/// imam" button appears: the app never fights the user's finger.
class SurahView extends StatefulWidget {
  const SurahView({
    super.key,
    required this.quran,
    required this.surah,
    required this.current,
    required this.confident,
    this.textScale = 1.0,
    this.manualHold = const Duration(seconds: 8),
  });

  final Quran quran;
  final int surah;

  /// The ayah to highlight (null: nothing highlighted).
  final Position? current;

  /// Full-strength highlight when following; softer when not sure.
  final bool confident;
  final double textScale;
  final Duration manualHold;

  @override
  State<SurahView> createState() => _SurahViewState();
}

class _SurahViewState extends State<SurahView> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  DateTime? _manualUntil;
  Timer? _holdTimer;

  bool get _following => _manualUntil == null || DateTime.now().isAfter(_manualUntil!);

  @override
  void didUpdateWidget(SurahView old) {
    super.didUpdateWidget(old);
    if (old.surah != widget.surah) {
      _keys.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    if (widget.current != old.current && _following) _scheduleFollow();
  }

  @override
  void initState() {
    super.initState();
    _scheduleFollow();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleFollow() => WidgetsBinding.instance.addPostFrameCallback((_) => _follow());

  void _follow({bool animate = true}) {
    final current = widget.current;
    if (!mounted || current == null || current.surah != widget.surah) return;
    final ctx = _keys[current.ayah]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
      _holdTimer?.cancel();
      setState(() => _manualUntil = DateTime.now().add(widget.manualHold));
      _holdTimer = Timer(widget.manualHold, () {
        if (mounted) {
          setState(() => _manualUntil = null);
          _follow();
        }
      });
    }
    return false;
  }

  void _backToImam() {
    _holdTimer?.cancel();
    setState(() => _manualUntil = null);
    _follow();
  }

  @override
  Widget build(BuildContext context) {
    final surah = widget.quran.surah(widget.surah);
    final verses = widget.quran.surahVerses(widget.surah);
    final fontSize = 26.0 * widget.textScale;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (surah.hasBasmala)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontFamily: quranFont, fontSize: fontSize * 0.9, color: context.colors.muted),
                    ),
                  ),
                for (final v in verses)
                  _AyahBlock(
                    key: _keys.putIfAbsent(v.ayah, GlobalKey.new),
                    verse: v,
                    fontSize: fontSize,
                    highlighted: widget.current?.verseId == v.id,
                    confident: widget.confident,
                  ),
              ],
            ),
          ),
        ),
        if (!_following && widget.current?.surah == widget.surah)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: _backToImam,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('Back to the imam'),
              ),
            ),
          ),
      ],
    );
  }
}

class _AyahBlock extends StatelessWidget {
  const _AyahBlock({
    super.key,
    required this.verse,
    required this.fontSize,
    required this.highlighted,
    required this.confident,
  });

  final Verse verse;
  final double fontSize;
  final bool highlighted;
  final bool confident;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? context.colors.highlight.withOpacity(confident ? 1 : 0.5) : Colors.transparent;
    return Semantics(
      label: 'Ayah ${verse.ayah}',
      selected: highlighted,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${verse.text} '),
              TextSpan(
                text: '﴿${arabicDigits(verse.ayah)}﴾',
                style: TextStyle(color: context.colors.gold, fontSize: fontSize * 0.8),
              ),
            ],
          ),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.justify,
          style: TextStyle(fontFamily: quranFont, fontSize: fontSize, height: 2.0, color: context.scheme.onSurface),
        ),
      ),
    );
  }
}

/// 29 -> ٢٩
String arabicDigits(int n) => n.toString().split('').map((d) => String.fromCharCode(0x0660 + int.parse(d))).join();
