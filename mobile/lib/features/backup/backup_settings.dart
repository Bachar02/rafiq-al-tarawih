import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/app_scope.dart';
import '../../app/components/settings_group.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/backup.dart';
import '../../l10n/l10n.dart';

/// Settings → Your data: save everything to a file, or bring it back from
/// one. For deleting Rafiq without losing anything, or a new phone.
class BackupSettings extends ConsumerWidget {
  const BackupSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final canOpen = ref.watch(backupFilesProvider).canOpen;
    return RubricGroup(
      label: l.groupData,
      children: [
        RubricRow(
          label: l.backupSave,
          detail: l.backupSaveDetail,
          trailing: Icon(Icons.save_alt, color: c.inkSecondary),
          onTap: () => saveBackup(context, ref),
        ),
        if (canOpen)
          RubricRow(
            label: l.backupRestore,
            detail: l.backupRestoreDetail,
            trailing: Icon(Icons.settings_backup_restore, color: c.inkSecondary),
            onTap: () => restoreBackup(context, ref),
          ),
      ],
    );
  }
}

/// Everything held in memory and not yet stored, stored now, so the backup
/// has the latest of it.
Future<void> _flush(WidgetRef ref) async {
  await ref.read(readingPositionProvider.notifier).flush();
  await ref.read(readingSessionProvider.notifier).flush();
  await ref.read(taraweehLedgerProvider.notifier).flush();
}

/// Saves a backup where the user chooses. Says whether it was saved.
Future<void> saveBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  try {
    await _flush(ref);
    final backup = Backup.capture(ref.read(preferencesProvider), ref.read(clockProvider)());
    if (!await ref.read(backupFilesProvider).save(backup.fileName, backup.encode())) return; // cancelled
    messenger.showSnackBar(SnackBar(content: Text(l.backupSaved)));
  } catch (e, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'backup'));
    messenger.showSnackBar(SnackBar(content: Text(l.backupSaveFailed)));
  }
}

/// Restores a backup the user picks, after saying what it replaces. The app
/// then opens again from what was restored (see [AppScope.reopen]).
Future<void> restoreBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final Backup backup;
  try {
    final raw = await ref.read(backupFilesProvider).open();
    if (raw == null) return; // cancelled
    backup = Backup.decode(raw);
  } on BackupException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.problem == BackupProblem.tooNew ? l.backupTooNew : l.backupNotABackup),
    ));
    return;
  } catch (e, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'backup'));
    messenger.showSnackBar(SnackBar(content: Text(l.backupOpenFailed)));
    return;
  }
  if (!context.mounted) return;
  final date = DateFormat.yMMMMd(l.localeName).add_jm().format(backup.createdAt);
  final sure = await showRubricSheet<bool>(
    context,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: l.backupRestoreAsk(date), explanation: l.backupRestoreWarning),
          const SizedBox(height: RubricSpace.s4),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.backupRestoreConfirm)),
          const SizedBox(height: RubricSpace.s2),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      ),
    ),
  );
  if (sure != true || !context.mounted) return;
  final prefs = ref.read(preferencesProvider);
  final scope = AppScope.maybeOf(context);
  if (scope == null) {
    // No scope to open again (not the app as main.dart builds it).
    await backup.restoreInto(prefs);
    return;
  }
  await scope.reopen(() => backup.restoreInto(prefs));
}
