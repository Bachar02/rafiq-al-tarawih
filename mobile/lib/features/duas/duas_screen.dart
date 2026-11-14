import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/settings_group.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/duas.dart';
import '../../l10n/l10n.dart';
import '../adhkar/adhkar_screen.dart' show DhikrCard;

/// The Duas screen: one row per purpose (forgiveness, distress, travel...),
/// each opening its duas.
class DuasScreen extends ConsumerWidget {
  const DuasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final categories = ref.watch(duasProvider).categories;
    return Scaffold(
      appBar: AppBar(title: Text(l.duas)),
      body: categories.isEmpty
          ? Center(child: Text(l.duasNone, style: RubricText.label.copyWith(color: c.inkSecondary)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, 0, RubricSpace.gutter, RubricSpace.s8),
              children: [
                RubricGroup(
                  children: [
                    for (final category in categories)
                      RubricRow(
                        label: category.title(l.localeName),
                        detail: l.duasCount(category.duas.length),
                        trailing: Icon(Icons.chevron_right, color: c.inkSecondary),
                        onTap: () => AppRoutes.duaList(context, category.id),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// The duas of one purpose, to read.
class DuaListScreen extends ConsumerWidget {
  const DuaListScreen({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final duas = ref.watch(duasProvider);
    final DuaCategory? category = duas.category(categoryId);
    return Scaffold(
      appBar: AppBar(title: Text(category?.title(l.localeName) ?? l.duas)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s4, RubricSpace.gutter, RubricSpace.s12),
        children: [
          if (category != null)
            for (final dua in category.duas)
              Padding(
                padding: const EdgeInsets.only(bottom: RubricSpace.s3),
                child: DhikrCard(dhikr: dua, sourceNames: duas.sourcesOf(dua, l.localeName)),
              ),
        ],
      ),
    );
  }
}
