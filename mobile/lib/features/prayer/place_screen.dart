import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/notice.dart';
import '../../app/components/settings_group.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/cities.dart';
import '../../l10n/l10n.dart';
import '../../services/location.dart';
import 'prayer_controller.dart';

/// Where the prayer times are for: the phone's own position, or a town
/// typed and chosen from the bundled list. Pops once a place is set.
class PlaceScreen extends ConsumerStatefulWidget {
  const PlaceScreen({super.key, this.search = false});

  /// Open ready to type a town's name (the keyboard up).
  final bool search;

  @override
  ConsumerState<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends ConsumerState<PlaceScreen> {
  final _field = TextEditingController();
  String _query = '';
  bool _locating = false;
  PlaceFailure? _failure;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _failure = null;
    });
    final failure = await ref.read(prayerSettingsProvider.notifier).useLocation();
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _locating = false;
        _failure = failure;
      });
    }
  }

  Future<void> _choose(City city) async {
    final saved = await ref.read(prayerSettingsProvider.notifier).choose(city);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _failure = const PlaceFailure.notSaved());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final language = l.localeName;
    final cities = ref.watch(citiesProvider);
    final query = _query.trim();
    final current = ref.watch(prayerSettingsProvider.select((s) => s.place));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsetsDirectional.only(end: RubricSpace.s4),
          child: TextField(
            controller: _field,
            autofocus: widget.search,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: l.searchCity,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l.clear,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _field.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            // A scan of some 60,000 short strings: milliseconds.
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
      ),
      body: switch (cities) {
        AsyncData(:final value) when query.isNotEmpty => _results(l, language, value, query),
        AsyncLoading() when query.isNotEmpty => const Center(child: CircularProgressIndicator()),
        _ => ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s2, RubricSpace.gutter, RubricSpace.s8),
            children: [
              RubricGroup(
                children: [
                  RubricRow(
                    label: l.useMyLocation,
                    detail: _locating ? l.locating : l.useMyLocationDetail,
                    selected: current?.fromLocation ?? false,
                    trailing: _locating
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.my_location, color: c.inkSecondary),
                    onTap: _locate,
                  ),
                ],
              ),
              if (_failure != null) ...[
                const SizedBox(height: RubricSpace.s4),
                PlaceFailureNotice(failure: _failure!),
              ],
              const SizedBox(height: RubricSpace.s4),
              Text(l.placeHelp, style: RubricText.caption.copyWith(color: c.inkSecondary)),
            ],
          ),
      },
    );
  }

  Widget _results(AppLocalizations l, String language, Cities cities, String query) {
    final found = cities.search(query);
    if (found.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(RubricSpace.s6),
        child: Text(
          l.noCityFound(query),
          textAlign: TextAlign.center,
          style: RubricText.label.copyWith(color: context.colors.inkSecondary),
        ),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s2),
      itemCount: found.length,
      itemBuilder: (context, i) {
        final city = found[i];
        return RubricRow(
          label: city.nameIn(language),
          detail: cities.countryName(city.countryCode, language),
          onTap: () => _choose(city),
        );
      },
    );
  }
}

/// Why the place could not be set, and the one thing that puts it right.
class PlaceFailureNotice extends ConsumerWidget {
  const PlaceFailureNotice({super.key, required this.failure});

  final PlaceFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final location = failure.location;
    final inSettings = location == LocationFailure.deniedForever || location == LocationFailure.serviceOff;
    return Notice(
      icon: location == null ? Icons.error_outline : Icons.location_off_outlined,
      title: switch (location) {
        null => l.prayerNotSaved,
        LocationFailure.denied => l.locationDenied,
        LocationFailure.deniedForever => l.locationDeniedForever,
        LocationFailure.serviceOff => l.locationServiceOff,
        LocationFailure.unavailable => l.locationUnavailable,
      },
      actionLabel: inSettings ? l.openSettings : null,
      onAction: inSettings ? () => ref.read(locationProvider).openSettings(location!) : null,
      alert: true,
    );
  }
}
