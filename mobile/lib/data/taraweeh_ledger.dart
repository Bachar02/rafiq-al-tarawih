/// Where Taraweeh stopped, inferred from what the imam was heard reciting,
/// night by night (PLAN.md §39).
///
/// One saved position, overwritten by the latest confident ayah, was confused
/// by everything else recited in the mosque: Al-Fatiha, Witr's short surahs,
/// ayahs quoted in qunut or a khatera, Isha. Instead, each night keeps the
/// **runs** of ayahs heard one after the other, and the stopping point is the
/// end of the night's **main passage**: its longest established runs, linked
/// in order, preferring the one that continues the night before. A quotation
/// is a run of one or two ayahs and never counts; Witr starts a new run in
/// another surah and does not link to the passage; a night whose evidence is
/// too weak or two-sided keeps the progress of the night before. The user can
/// correct any night afterwards; nothing is asked during prayer.
///
/// Pure and immutable: the controller feeds it committed results
/// ([observe]) and the user's corrections ([correct]), and saves it.
library;

import 'package:flutter/foundation.dart';

import 'quran.dart';

/// Ayahs heard one after the other within a night (a few may be skipped:
/// a short ayah can end inside one chunk of audio).
@immutable
class Run {
  const Run({
    required this.first,
    required this.last,
    required this.ayahs,
    required this.from,
    required this.to,
    this.ahead,
  });

  final int first;

  /// The furthest ayah the run reached, confirmed.
  final int last;

  /// A skip ahead of [last] (more than one ayah), not yet confirmed: it counts
  /// once the imam is heard at or after it, and is dropped if he is heard
  /// behind it (a garbled chunk can match a few ayahs on for one result).
  final int? ahead;

  /// Times the run moved forward: distinct ayahs heard, about.
  final int ayahs;
  final DateTime from;
  final DateTime to;

  /// [verseId] heard at [at], within reach of this run.
  Run _heard(int verseId, DateTime at) {
    final skip = ahead;
    // A repeat; a pending skip was a blip.
    if (verseId <= last) return Run(first: first, last: last, ayahs: ayahs, from: from, to: at);
    if (skip != null && verseId >= skip) {
      return Run(first: first, last: verseId, ayahs: ayahs + (verseId > skip ? 2 : 1), from: from, to: at);
    }
    if (verseId == last + 1) return Run(first: first, last: verseId, ayahs: ayahs + 1, from: from, to: at);
    return Run(first: first, last: last, ayahs: ayahs, from: from, to: at, ahead: verseId);
  }

  Map<String, Object> toJson() => {
        'first': first,
        'last': last,
        'ayahs': ayahs,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        if (ahead != null) 'ahead': ahead!,
      };

  static Run? fromJson(Object? json) {
    if (json is! Map) return null;
    final first = json['first'], last = json['last'], ayahs = json['ayahs'], ahead = json['ahead'];
    final from = DateTime.tryParse('${json['from']}'), to = DateTime.tryParse('${json['to']}');
    if (first is! int || last is! int || ayahs is! int || from == null || to == null) return null;
    if (!_valid(first) || !_valid(last) || last < first || ayahs < 1) return null;
    if (ahead != null && (ahead is! int || ahead <= last + 1 || !_valid(ahead))) return null;
    return Run(first: first, last: last, ayahs: ayahs, from: from.toLocal(), to: to.toLocal(), ahead: ahead as int?);
  }

  @override
  bool operator ==(Object other) =>
      other is Run &&
      other.first == first &&
      other.last == last &&
      other.ayahs == ayahs &&
      other.from == from &&
      other.to == to &&
      other.ahead == ahead;

  @override
  int get hashCode => Object.hash(first, last, ayahs, from, to, ahead);

  @override
  String toString() => 'Run($first..$last${ahead == null ? '' : ' (ahead $ahead?)'}, $ayahs)';
}

/// Who set a night's stopping point by hand.
enum FixSource {
  /// The user, afterwards ("Taraweeh ended here").
  user,

  /// The single saved position of earlier versions, carried over once.
  legacy,
}

/// One night of Taraweeh: its runs and, if set by hand, where it ended.
@immutable
class Night {
  const Night({required this.key, this.runs = const [], this.fixed, this.fixedBy, this.fixedAt});

  /// The night's date (`2027-02-08`): the local date 12 hours earlier, so a
  /// prayer after midnight belongs to the evening it started.
  final String key;
  final List<Run> runs;

  /// Where the night ended, set by hand: it overrides the runs.
  final int? fixed;
  final FixSource? fixedBy;
  final DateTime? fixedAt;

  /// The last time anything was heard or set this night.
  DateTime? get lastAt {
    DateTime? last = fixedAt;
    for (final r in runs) {
      if (last == null || r.to.isAfter(last)) last = r.to;
    }
    return last;
  }

  Night _with({List<Run>? runs, int? fixed, FixSource? fixedBy, DateTime? fixedAt}) => Night(
        key: key,
        runs: runs ?? this.runs,
        fixed: fixed ?? this.fixed,
        fixedBy: fixedBy ?? this.fixedBy,
        fixedAt: fixedAt ?? this.fixedAt,
      );

  Map<String, Object?> toJson() => {
        'night': key,
        'runs': [for (final r in runs) r.toJson()],
        if (fixed != null) 'fixed': fixed,
        if (fixedBy != null) 'by': fixedBy!.name,
        if (fixedAt != null) 'fixed_at': fixedAt!.toUtc().toIso8601String(),
      };

  /// Null if the night itself is unreadable; unreadable runs are dropped
  /// ([dropped] is told).
  static Night? fromJson(Object? json, {void Function()? dropped}) {
    if (json is! Map) return null;
    final key = json['night'], list = json['runs'];
    if (key is! String || !_nightKey.hasMatch(key) || list is! List) return null;
    final runs = <Run>[];
    for (final item in list) {
      final run = Run.fromJson(item);
      run == null ? dropped?.call() : runs.add(run);
    }
    final fixed = json['fixed'];
    final by = FixSource.values.asNameMap()[json['by']];
    final fixedAt = DateTime.tryParse('${json['fixed_at']}');
    final hasFix = fixed is int && _valid(fixed) && by != null && fixedAt != null;
    if (json.containsKey('fixed') && !hasFix) dropped?.call();
    return Night(
      key: key,
      runs: List.unmodifiable(runs),
      fixed: hasFix ? fixed : null,
      fixedBy: hasFix ? by : null,
      fixedAt: hasFix ? fixedAt.toLocal() : null,
    );
  }

  @override
  String toString() => 'Night($key, $runs${fixed == null ? '' : ', fixed $fixed by ${fixedBy!.name}'})';
}

/// Where Taraweeh stopped, and on what evidence.
@immutable
class TaraweehProgress {
  const TaraweehProgress({
    required this.verseId,
    required this.night,
    required this.at,
    required this.ayahs,
    this.fixedBy,
  });

  /// The last ayah of the main passage (or the one set by hand).
  final int verseId;

  /// The night it was reached ([Night.key]).
  final String night;

  /// When it was last heard or set.
  final DateTime at;

  /// Ayahs of the main passage heard that night (0 when set by hand).
  final int ayahs;

  /// Set by hand, or null if inferred.
  final FixSource? fixedBy;

  @override
  bool operator ==(Object other) =>
      other is TaraweehProgress &&
      other.verseId == verseId &&
      other.night == night &&
      other.at == at &&
      other.ayahs == ayahs &&
      other.fixedBy == fixedBy;

  @override
  int get hashCode => Object.hash(verseId, night, at, ayahs, fixedBy);

  @override
  String toString() => 'TaraweehProgress($verseId, $night, $ayahs ayahs${fixedBy == null ? '' : ', ${fixedBy!.name}'})';
}

/// What one night says about where Taraweeh stopped.
@immutable
class NightVerdict {
  const NightVerdict._(this.end, this.ayahs, this.at, this.reason);

  /// The night's stopping point; null when it does not say ([reason]).
  final int? end;
  final int ayahs;
  final DateTime? at;
  final VerdictReason reason;

  bool get reliable => end != null;
}

enum VerdictReason {
  /// The main passage, decisively.
  passage,

  /// Set by hand.
  fixed,

  /// No passage of [TaraweehLedger.minAyahs] ayahs: too little was heard.
  weak,

  /// Two passages of about the same length and neither continues the night
  /// before: which one was Taraweeh is unknown.
  contradictory,
}

/// Every night recorded, oldest first. Immutable.
@immutable
class TaraweehLedger {
  const TaraweehLedger([this.nights = const []]);

  static const empty = TaraweehLedger();

  final List<Night> nights;

  // -- the rules ------------------------------------------------------------

  /// Fewer ayahs than this in a row are a quotation (qunut, a khatera), not
  /// the night's recitation: such a run never counts.
  static const minAyahs = 3;

  /// An ayah at most this far after a run's last continues it (a short ayah
  /// can end inside one chunk of audio and never be reported).
  static const nearGap = 3;

  /// A later established run starting at most this many ayahs after an
  /// earlier one's end, in the same surah or the next, is the same passage
  /// (recognition lost the imam for a while). Never across a skipped surah:
  /// that is Witr, after Taraweeh.
  static const linkGap = 40;

  /// A passage starting this close to where the night before ended continues
  /// it (the imam may repeat a few ayahs or skip a little).
  static const continueBefore = 10;
  static const continueAfter = 40;

  /// History kept: two Ramadans, and runs per night.
  static const maxNights = 60;
  static const maxRuns = 48;

  /// The night [at] belongs to: its local date 12 hours earlier.
  static String nightOf(DateTime at) {
    final d = at.toLocal().subtract(const Duration(hours: 12));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  }

  // -- input ----------------------------------------------------------------

  /// The imam was heard reciting [verseId], committed (a final result the
  /// engine is sure of, or "the imam is here"). Al-Fatiha, recited at every
  /// rakʿah, is never part of the night's passage.
  TaraweehLedger observe(int verseId, DateTime at) {
    if (!_valid(verseId) || verseId <= _fatihaLast) return this;
    final key = nightOf(at);
    final night = _night(key) ?? Night(key: key);
    final runs = [...night.runs];
    // The most recent run this ayah repeats or continues.
    var index = -1;
    for (var i = 0; i < runs.length; i++) {
      final r = runs[i];
      final reach = (r.ahead ?? r.last) + nearGap;
      if (verseId >= r.first && verseId <= reach && (index < 0 || !r.to.isBefore(runs[index].to))) index = i;
    }
    if (index >= 0) {
      runs[index] = runs[index]._heard(verseId, at);
    } else {
      runs.add(Run(first: verseId, last: verseId, ayahs: 1, from: at, to: at));
      if (runs.length > maxRuns) {
        // Forget the oldest single ayah (a quotation), else the oldest run.
        final single = runs.indexWhere((r) => r.ayahs == 1);
        runs.removeAt(single >= 0 ? single : 0);
      }
    }
    return _put(night._with(runs: List.unmodifiable(runs)));
  }

  /// "Taraweeh ended at [verseId]": the user's correction, for the latest
  /// night (or, with none, the night [at] belongs to). Overrides whatever
  /// was inferred for it.
  TaraweehLedger correct(int verseId, DateTime at) {
    if (!_valid(verseId)) return this;
    final night = nights.isNotEmpty ? nights.last : Night(key: nightOf(at));
    return _put(night._with(fixed: verseId, fixedBy: FixSource.user, fixedAt: at));
  }

  /// The single position of earlier versions, as a night set by hand.
  static TaraweehLedger fromLegacy(int verseId, DateTime savedAt) => !_valid(verseId)
      ? empty
      : TaraweehLedger([Night(key: nightOf(savedAt), fixed: verseId, fixedBy: FixSource.legacy, fixedAt: savedAt)]);

  // -- output ---------------------------------------------------------------

  /// Where Taraweeh stopped: the latest night that says so reliably. A weak
  /// or contradictory night keeps the progress of the nights before it.
  TaraweehProgress? progress(Quran quran) {
    TaraweehProgress? out;
    for (final night in nights) {
      final verdict = judge(night, out?.verseId, quran);
      if (verdict.reliable) {
        out = TaraweehProgress(
          verseId: verdict.end!,
          night: night.key,
          at: verdict.at!,
          ayahs: verdict.ayahs,
          fixedBy: night.fixed != null ? night.fixedBy : null,
        );
      }
    }
    return out;
  }

  /// What [night] says, given where the nights before it ended ([before]).
  static NightVerdict judge(Night night, int? before, Quran quran) {
    if (night.fixed != null) return NightVerdict._(night.fixed, 0, night.fixedAt, VerdictReason.fixed);
    final passages = _passages(night.runs, quran);
    if (passages.isEmpty) return const NightVerdict._(null, 0, null, VerdictReason.weak);
    _Passage? best, continuing;
    for (final p in passages) {
      if (best == null || p.ayahs > best.ayahs || (p.ayahs == best.ayahs && p.to.isAfter(best.to))) best = p;
      final continues = before != null && p.first >= before - continueBefore && p.first <= before + 1 + continueAfter;
      if (continues && (continuing == null || p.ayahs > continuing.ayahs)) continuing = p;
    }
    // The night continues the one before unless something else dwarfs it.
    if (continuing != null && continuing.ayahs * 2 >= best!.ayahs) {
      return NightVerdict._(continuing.last, continuing.ayahs, continuing.to, VerdictReason.passage);
    }
    // Otherwise the longest passage, if clearly longer than any other.
    final runnerUp = passages.where((p) => !identical(p, best)).fold<int>(0, (m, p) => p.ayahs > m ? p.ayahs : m);
    if (best!.ayahs < runnerUp + minAyahs) return const NightVerdict._(null, 0, null, VerdictReason.contradictory);
    return NightVerdict._(best.last, best.ayahs, best.to, VerdictReason.passage);
  }

  /// The night's established runs (at least [minAyahs]), linked in time
  /// order into passages.
  static List<_Passage> _passages(List<Run> runs, Quran quran) {
    final established = [
      for (final r in runs)
        if (r.ayahs >= minAyahs) r
    ]..sort((a, b) => a.from.compareTo(b.from));
    final passages = <_Passage>[];
    for (final r in established) {
      _Passage? into;
      for (final p in passages) {
        final step = quran.verse(r.first).surah - quran.verse(p.last).surah;
        final links =
            r.first > p.last && r.first <= p.last + linkGap && (step == 0 || step == 1) && !r.from.isBefore(p.to);
        if (links && (into == null || p.to.isAfter(into.to))) into = p;
      }
      if (into == null) {
        passages.add(_Passage(r.first, r.last, r.ayahs, r.to));
      } else {
        into
          ..last = r.last
          ..ayahs += r.ayahs
          ..to = r.to;
      }
    }
    return passages;
  }

  // -- storage --------------------------------------------------------------

  Map<String, Object> toJson() => {
        'v': 1,
        'nights': [for (final n in nights) n.toJson()],
      };

  /// Null if unreadable as a whole (the store keeps the original aside);
  /// [dropped] is told when some entries were unreadable and left out.
  static TaraweehLedger? fromJson(Object? json, {void Function()? dropped}) {
    if (json is! Map || json['v'] != 1 || json['nights'] is! List) return null;
    final byKey = <String, Night>{};
    for (final item in json['nights'] as List) {
      final night = Night.fromJson(item, dropped: dropped);
      if (night == null || byKey.containsKey(night.key)) {
        dropped?.call();
        continue;
      }
      byKey[night.key] = night;
    }
    final nights = byKey.values.toList()..sort((a, b) => a.key.compareTo(b.key));
    return TaraweehLedger(List.unmodifiable(nights));
  }

  Night? _night(String key) {
    for (final n in nights) {
      if (n.key == key) return n;
    }
    return null;
  }

  /// [night] in its place (nights stay in date order), history capped.
  TaraweehLedger _put(Night night) {
    final out = [
      for (final n in nights)
        if (n.key != night.key) n,
      night,
    ]..sort((a, b) => a.key.compareTo(b.key));
    return TaraweehLedger(List.unmodifiable(out.length > maxNights ? out.sublist(out.length - maxNights) : out));
  }

  @override
  String toString() => 'TaraweehLedger($nights)';
}

/// Established runs linked into one passage (scratch, while judging).
class _Passage {
  _Passage(this.first, this.last, this.ayahs, this.to);

  final int first;
  int last;
  int ayahs;
  DateTime to;
}

/// Al-Fatiha is verses 1 to 7.
const _fatihaLast = 7;

final _nightKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool _valid(int id) => id >= 1 && id <= Quran.verseCount;
