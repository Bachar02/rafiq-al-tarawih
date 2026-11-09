import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adhkar.dart';
import '../../data/khatm.dart' show dateOnly;
import '../../l10n/l10n.dart';

/// Today's counts, kept as the user taps. A count shows at once and is then
/// saved: losing one tick to a full disk is harmless, waiting for it is not.
class AdhkarDayController extends Notifier<AdhkarDay> {
  @override
  AdhkarDay build() {
    final saved = ref.read(adhkarStoreProvider).load();
    return saved != null && saved.day == _today ? saved : AdhkarDay(_today);
  }

  DateTime get _today => dateOnly(ref.read(clockProvider)());

  /// The counts as of now: past midnight, a new day from zero.
  AdhkarDay get today => state.day == _today ? state : AdhkarDay(_today);

  /// One more time said.
  Future<void> count(AdhkarCollection collection, Dhikr dhikr) => _set(today.counted(collection, dhikr));

  /// [collection] from the start; returns the counts before, for undo.
  Future<AdhkarDay> reset(AdhkarCollection collection) async {
    final before = today;
    await _set(before.reset(collection));
    return before;
  }

  /// Back to [day] (undo a reset), if it is still today.
  Future<void> restore(AdhkarDay day) async {
    if (day.day == _today) await _set(day);
  }

  Future<void> _set(AdhkarDay day) async {
    state = day;
    await ref.read(adhkarStoreProvider).save(day);
  }
}

/// The adhkar of this time of day, if any: the morning until late morning,
/// the evening from mid-afternoon, then the night's before sleep. A gentle
/// suggestion only (it does not know the prayer times), so it is a word on
/// a row, never a reordering of the list.
AdhkarCollection? adhkarNow(DateTime now) => switch (now.hour) {
      >= 3 && < 11 => AdhkarCollection.morning,
      >= 15 && < 21 => AdhkarCollection.evening,
      >= 21 || < 3 => AdhkarCollection.sleep,
      _ => null,
    };

String collectionTitle(AppLocalizations l, AdhkarCollection c) => switch (c) {
      AdhkarCollection.morning => l.adhkarMorning,
      AdhkarCollection.evening => l.adhkarEvening,
      AdhkarCollection.prayer => l.adhkarPrayer,
      AdhkarCollection.sleep => l.adhkarSleep,
      AdhkarCollection.anytime => l.adhkarAnytime,
    };

/// When the collection is said.
String collectionWhen(AppLocalizations l, AdhkarCollection c) => switch (c) {
      AdhkarCollection.morning => l.adhkarMorningWhen,
      AdhkarCollection.evening => l.adhkarEveningWhen,
      AdhkarCollection.prayer => l.adhkarPrayerWhen,
      AdhkarCollection.sleep => l.adhkarSleepWhen,
      AdhkarCollection.anytime => l.adhkarAnytimeWhen,
    };

/// "Al-Bukhari and Muslim": the sources, joined in the interface language.
String sourcesLabel(AppLocalizations l, List<String> names) {
  if (names.isEmpty) return '';
  final joined =
      names.length == 1 ? names.single : l.adhkarSources(names.sublist(0, names.length - 1).join(', '), names.last);
  // A sentence starts with a capital in English and French: al-Bukhari → Al-Bukhari.
  return l.localeName == 'ar' ? joined : joined[0].toUpperCase() + joined.substring(1);
}
