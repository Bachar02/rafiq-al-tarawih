import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../app/components/choice_sheet.dart';
import '../../app/components/quran_text.dart';
import '../../app/components/settings_group.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/recognition/endpoint.dart';
import '../../data/settings.dart';
import '../../data/study_text.dart';
import '../../l10n/l10n.dart';
import '../../services/server_health.dart';
import '../adhkar/dhikr_reminders.dart';
import '../bench/asr_bench_screen.dart';
import '../progress/progress_screen.dart' show ReminderSettings;
import '../study/study_source_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: ref.read(settingsProvider).serverAddress);
  }

  String? _addressError;
  ServerHealth? _health;
  bool _testing = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _saveAddress() async {
    final error = validateServerAddress(_address.text);
    setState(() => _addressError = error);
    if (error == null) {
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(serverAddress: _address.text.trim()));
    }
  }

  Future<void> _test() async {
    await _saveAddress();
    if (_addressError != null) return;
    setState(() {
      _testing = true;
      _health = null;
    });
    final result = await ref.read(healthCheckerProvider)(_address.text.trim());
    if (mounted) {
      setState(() {
        _testing = false;
        _health = result;
      });
    }
  }

  /// A sheet of options, the current one checked.
  Future<T?> _choose<T>({
    required String title,
    String? explanation,
    required List<T> options,
    required T current,
    required String Function(T) label,
  }) =>
      showRubricSheet<T>(
        context,
        builder: (context) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(title: title, explanation: explanation),
              const SizedBox(height: RubricSpace.s4),
              RubricGroup(
                children: [
                  for (final option in options)
                    RubricRow(
                      label: label(option),
                      selected: option == current,
                      trailing: option == current ? Icon(Icons.check, color: context.colors.ink, size: 20) : null,
                      onTap: () => Navigator.pop(context, option),
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  Future<void> _chooseAppearance(ThemeMode current) async {
    final l = context.l10n;
    final mode = await _choose(
      title: l.appearance,
      explanation: l.appearanceExplanation,
      options: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
      current: current,
      label: (m) => appearanceLabel(l, m),
    );
    if (mode != null) await ref.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: mode));
  }

  Future<void> _chooseLayout(ReadingLayout current) async {
    final l = context.l10n;
    final layout = await _choose(
      title: l.layout,
      explanation: l.layoutExplanation,
      options: ReadingLayout.values,
      current: current,
      label: (r) => layoutLabel(l, r),
    );
    if (layout != null) await ref.read(settingsProvider.notifier).update((s) => s.copyWith(readingLayout: layout));
  }

  Future<void> _chooseGoal(int current) async {
    final l = context.l10n;
    final goal = await _choose(
      title: l.dailyGoal,
      explanation: l.dailyGoalExplanation,
      options: AppSettings.dailyGoals,
      current: current,
      label: (pages) => goalLabel(l, pages),
    );
    if (goal != null) await ref.read(settingsProvider.notifier).update((s) => s.copyWith(dailyGoalPages: goal));
  }

  Future<void> _chooseLanguage(AppLanguage current) async {
    final l = context.l10n;
    final language = await _choose(
      title: l.language,
      explanation: l.languageExplanation,
      options: AppLanguage.values,
      current: current,
      label: (a) => languageLabel(l, a),
    );
    if (language != null) await ref.read(settingsProvider.notifier).update((s) => s.copyWith(language: language));
  }

  /// 1.5 -> "1.5" (or "1,5"), 2.0 -> "2", in the interface language.
  String _seconds(double s) => NumberFormat('0.##', Localizations.localeOf(context).toLanguageTag()).format(s);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    final ui = Localizations.localeOf(context).languageCode;
    final translation = ref.watch(studySourceProvider(StudyKind.translation));
    final tafsir = ref.watch(studySourceProvider(StudyKind.tafsir));
    final texts = ref.watch(studyCatalogProvider).sources;
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, 0, RubricSpace.gutter, RubricSpace.s8),
        children: [
          RubricGroup(
            label: l.groupReading,
            children: [
              RubricRow(
                label: l.quranTextSize,
                value: '${(settings.textScale * 100).round()}%',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TextSizeScreen())),
              ),
              RubricRow(
                label: l.layout,
                value: layoutLabel(l, settings.readingLayout),
                onTap: () => _chooseLayout(settings.readingLayout),
              ),
              RubricRow(
                label: l.dailyGoal,
                value: goalLabel(l, settings.dailyGoalPages),
                onTap: () => _chooseGoal(settings.dailyGoalPages),
              ),
              RubricRow(
                label: l.appearance,
                value: appearanceLabel(l, settings.themeMode),
                onTap: () => _chooseAppearance(settings.themeMode),
              ),
              RubricRow(
                label: l.language,
                value: languageLabel(l, settings.language),
                onTap: () => _chooseLanguage(settings.language),
              ),
            ],
          ),
          const ReminderSettings(),
          const DhikrReminderSettings(),
          if (translation != null || tafsir != null)
            RubricGroup(
              label: l.translationAndTafsir,
              children: [
                if (translation != null)
                  RubricRow(
                    label: l.translation,
                    value: translation.name(ui),
                    onTap: () => chooseStudySource(context, ref, StudyKind.translation),
                  ),
                if (tafsir != null)
                  RubricRow(
                    label: l.tafsir,
                    value: tafsir.name(ui),
                    onTap: () => chooseStudySource(context, ref, StudyKind.tafsir),
                  ),
              ],
            ),
          RubricGroup(
            label: l.groupTaraweeh,
            children: [
              RubricRow(
                label: l.darkDuringTaraweeh,
                detail: l.darkDuringTaraweehDetail,
                onTap: () => update((s) => s.copyWith(darkDuringTaraweeh: !s.darkDuringTaraweeh)),
                trailing: Switch(
                  value: settings.darkDuringTaraweeh,
                  onChanged: (v) => update((s) => s.copyWith(darkDuringTaraweeh: v)),
                ),
              ),
              RubricRow(
                label: l.keepScreenOn,
                detail: l.keepScreenOnDetail,
                onTap: () => update((s) => s.copyWith(keepScreenOn: !s.keepScreenOn)),
                trailing: Switch(
                  value: settings.keepScreenOn,
                  onChanged: (v) => update((s) => s.copyWith(keepScreenOn: v)),
                ),
              ),
            ],
          ),
          RubricGroup(
            label: l.groupRecitation,
            children: [
              RubricRow(label: l.riwaya, value: l.hafs),
              Padding(
                padding: const EdgeInsets.all(RubricSpace.s4),
                child: Text(l.hafsOnly, style: caption),
              ),
            ],
          ),
          RubricGroup(
            label: l.groupDeveloper,
            children: [
              RubricRow(
                label: l.showDiagnostics,
                detail: l.showDiagnosticsDetail,
                onTap: () => update((s) => s.copyWith(showDiagnostics: !s.showDiagnostics)),
                trailing: Switch(
                  value: settings.showDiagnostics,
                  onChanged: (v) => update((s) => s.copyWith(showDiagnostics: v)),
                ),
              ),
              RubricRow(
                label: l.useServer,
                detail: l.useServerDetail,
                onTap: () => update((s) => s.copyWith(useServer: !s.useServer)),
                trailing: Switch(
                  value: settings.useServer,
                  onChanged: (v) => update((s) => s.copyWith(useServer: v)),
                ),
              ),
              RubricRow(
                label: l.asrBench,
                detail: l.asrBenchDetail,
                trailing: Icon(Icons.chevron_right, color: c.inkSecondary),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AsrBenchScreen())),
              ),
              // Experimental, off by default (PLAN.md §33): last, so the rows
              // above keep their place.
              RubricRow(
                label: l.wordHighlight,
                detail: l.wordHighlightDetail,
                onTap: () => update((s) => s.copyWith(wordHighlight: !s.wordHighlight)),
                trailing: Switch(
                  value: settings.wordHighlight,
                  onChanged: (v) => update((s) => s.copyWith(wordHighlight: v)),
                ),
              ),
              if (settings.wordHighlight)
                RubricRow(
                  label: l.wordStale,
                  detail: l.wordStaleSeconds(_seconds(settings.wordStaleSeconds)),
                  trailing: Icon(Icons.chevron_right, color: c.inkSecondary),
                  onTap: () async {
                    final chosen = await showChoiceSheet<double>(
                      context,
                      title: l.wordStale,
                      options: AppSettings.wordStaleChoices,
                      current: settings.wordStaleSeconds,
                      label: (s) => l.wordStaleSeconds(_seconds(s)),
                    );
                    if (chosen != null) await update((s) => s.copyWith(wordStaleSeconds: chosen));
                  },
                ),
            ],
          ),
          // Development only: Taraweeh mode recognises on a computer.
          if (settings.useServer)
            RubricGroup(
              label: l.groupServer,
              children: [
                Padding(
                  padding: const EdgeInsets.all(RubricSpace.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.serverExplanation, style: caption),
                      const SizedBox(height: RubricSpace.s3),
                      TextField(
                        controller: _address,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        // An address reads left to right in every language.
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: l.serverAddress,
                          hintText: '192.168.1.5:8765',
                          errorText: _addressError,
                        ),
                        onSubmitted: (_) => _saveAddress(),
                        onEditingComplete: _saveAddress,
                      ),
                      const SizedBox(height: RubricSpace.s3),
                      Wrap(
                        spacing: RubricSpace.s3,
                        runSpacing: RubricSpace.s2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: _testing ? null : _test,
                            child: _testing
                                ? const SizedBox(
                                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(l.actionTestConnection),
                          ),
                          if (_health != null) _HealthText(_health!),
                        ],
                      ),
                      const SizedBox(height: RubricSpace.s3),
                      Text(l.serverHelp, style: caption),
                    ],
                  ),
                ),
              ],
            ),
          RubricGroup(
            label: l.groupAbout,
            children: [
              Padding(
                padding: const EdgeInsets.all(RubricSpace.s4),
                child: Text('${l.aboutLead}\n\n$_attributions${textAttributions(texts)}', style: caption),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Licences, named as their authors publish them (not translated).
const _attributions = 'Quran text: Tanzil Project (tanzil.net), Uthmani and Simple Clean v1.1, CC BY 3.0.\n'
    'Fonts: Amiri Quran, Amiri, Newsreader, IBM Plex Sans and IBM Plex Sans Arabic, '
    'SIL Open Font License 1.1.\n'
    'Adhkar: chosen and worded after Hisn al-Muslim by Sa’id ibn Ali ibn Wahf al-Qahtani, '
    'with their hadith sources; English and French meanings written for Rafiq.\n'
    'Prayer times: computed on the phone with adhan_dart (MIT), after Jean Meeus, Astronomical Algorithms.\n'
    'Towns and countries: GeoNames (geonames.org), CC BY 4.0.\n'
    'Speech model: Tarteel whisper-base-ar-quran, Apache 2.0.\n'
    'On-device runtime: sherpa-onnx (k2-fsa), Apache 2.0.';

/// QuranEnc's terms: name the publisher, QuranEnc.com and the version.
String textAttributions(List<StudySource> texts) => texts.isEmpty
    ? ''
    : '\nTranslations and tafsir, unchanged, from QuranEnc.com (Encyclopedia of the Noble Quran): '
        '${[for (final t in texts) '${t.name('en')} (${t.credit('en')}), version ${t.version}'].join('; ')}.';

String appearanceLabel(AppLocalizations l, ThemeMode mode) => switch (mode) {
      ThemeMode.dark => l.themeDark,
      ThemeMode.light => l.themeLight,
      ThemeMode.system => l.themeSystem,
    };

String goalLabel(AppLocalizations l, int pages) => pages == 0 ? l.dailyGoalOff : l.pagesCount(pages);

String layoutLabel(AppLocalizations l, ReadingLayout layout) => switch (layout) {
      ReadingLayout.scroll => l.layoutScroll,
      ReadingLayout.pages => l.layoutPages,
    };

/// Each language by its own name, so anyone can find theirs.
String languageLabel(AppLocalizations l, AppLanguage language) => switch (language) {
      AppLanguage.system => l.languageSystem,
      AppLanguage.en => 'English',
      AppLanguage.fr => 'Français',
      AppLanguage.ar => 'العربية',
    };

/// Quran text size, judged on the real font: a live preview of ayah 93:3.
class TextSizeScreen extends ConsumerWidget {
  const TextSizeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider.select((s) => s.textScale));
    final quran = ref.watch(quranProvider);
    final preview = quran.surahVerses(93)[2];
    final fontSize = RubricText.quranBody.fontSize! * scale;
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.quranTextSize)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s4, RubricSpace.gutter, RubricSpace.s8),
        children: [
          LayoutBuilder(
            builder: (context, constraints) => AyahBlock(
              verse: preview,
              tone: AyahTone.current,
              fontSize: fontSize,
              justify: justifyQuran(columnWidth: constraints.maxWidth, fontSize: fontSize),
            ),
          ),
          const SizedBox(height: RubricSpace.s6),
          Row(
            children: [
              Text(l.textSizeSize, style: RubricText.label.copyWith(color: c.ink)),
              const Spacer(),
              Text('${(scale * 100).round()}%', style: RubricText.label.copyWith(color: c.inkSecondary)),
            ],
          ),
          Slider(
            value: scale,
            min: AppSettings.minTextScale,
            max: AppSettings.maxTextScale,
            divisions: ((AppSettings.maxTextScale - AppSettings.minTextScale) / 0.05).round(),
            label: '${(scale * 100).round()}%',
            onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(textScale: v)),
          ),
          Text(l.textSizeNote, style: RubricText.caption.copyWith(color: c.inkSecondary)),
        ],
      ),
    );
  }
}

class _HealthText extends StatelessWidget {
  const _HealthText(this.health);
  final ServerHealth health;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final ms = health.latency?.inMilliseconds ?? 0;
    final (icon, color, text) = !health.reachable
        ? (Icons.wifi_off_outlined, c.signal, health.error ?? l.healthFailed)
        : health.asr
            ? (Icons.check, c.ink, l.healthConnected(ms, health.device ?? l.healthReadyOnFirstUse))
            : (Icons.info_outline, c.signal, l.healthNoAsr(ms));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: RubricSpace.s2),
        Flexible(child: Text(text, style: RubricText.caption.copyWith(color: color))),
      ],
    );
  }
}
