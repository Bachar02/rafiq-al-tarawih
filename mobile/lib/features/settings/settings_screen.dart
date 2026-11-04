import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/quran_text.dart';
import '../../app/components/settings_group.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/recognition/endpoint.dart';
import '../../data/settings.dart';
import '../../services/server_health.dart';
import '../bench/asr_bench_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _address = TextEditingController(text: ref.read(settingsProvider).serverAddress);
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

  Future<void> _chooseAppearance(ThemeMode current) async {
    final mode = await showRubricSheet<ThemeMode>(
      context,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(title: 'Appearance', explanation: 'Dark is designed for prayer at night.'),
            const SizedBox(height: RubricSpace.s4),
            RubricGroup(
              children: [
                for (final m in const [ThemeMode.dark, ThemeMode.light, ThemeMode.system])
                  RubricRow(
                    label: appearanceLabel(m),
                    selected: m == current,
                    trailing: m == current ? Icon(Icons.check, color: context.colors.ink, size: 20) : null,
                    onTap: () => Navigator.pop(context, m),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (mode != null) await ref.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: mode));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, 0, RubricSpace.gutter, RubricSpace.s8),
        children: [
          RubricGroup(
            label: 'Reading',
            children: [
              RubricRow(
                label: 'Quran text size',
                value: '${(settings.textScale * 100).round()}%',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TextSizeScreen())),
              ),
              RubricRow(
                label: 'Keep screen on while following',
                detail: 'Recommended during prayer',
                onTap: () => update((s) => s.copyWith(keepScreenOn: !s.keepScreenOn)),
                trailing: Switch(
                  value: settings.keepScreenOn,
                  onChanged: (v) => update((s) => s.copyWith(keepScreenOn: v)),
                ),
              ),
              RubricRow(
                label: 'Appearance',
                value: appearanceLabel(settings.themeMode),
                onTap: () => _chooseAppearance(settings.themeMode),
              ),
            ],
          ),
          RubricGroup(
            label: 'Recitation',
            children: [
              const RubricRow(label: 'Riwāya', value: 'Ḥafṣ ʿan ʿĀṣim'),
              Padding(
                padding: const EdgeInsets.all(RubricSpace.s4),
                child: Text(
                  'Rafiq recognises and numbers ayahs in the Ḥafṣ riwāya only. Qālūn and Warsh are not supported yet.',
                  style: caption,
                ),
              ),
            ],
          ),
          // Server build only: removed with on-device recognition.
          RubricGroup(
            label: 'Recognition server',
            children: [
              Padding(
                padding: const EdgeInsets.all(RubricSpace.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'This build recognises on a computer on the same Wi-Fi; it does not work without it.',
                      style: caption,
                    ),
                    const SizedBox(height: RubricSpace.s3),
                    TextField(
                      controller: _address,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Server address',
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
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Test connection'),
                        ),
                        if (_health != null) _HealthText(_health!),
                      ],
                    ),
                    const SizedBox(height: RubricSpace.s3),
                    Text(
                      'Start the server on the computer with:  python -m rafiq_server --host 0.0.0.0\n'
                      'then enter its Wi-Fi address and port. On the Android emulator, use 10.0.2.2:8765.',
                      style: caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          RubricGroup(
            label: 'Developer',
            children: [
              RubricRow(
                label: 'Show diagnostics',
                detail: 'What the speech model hears, for testing',
                onTap: () => update((s) => s.copyWith(showDiagnostics: !s.showDiagnostics)),
                trailing: Switch(
                  value: settings.showDiagnostics,
                  onChanged: (v) => update((s) => s.copyWith(showDiagnostics: v)),
                ),
              ),
              RubricRow(
                label: 'On-device speech benchmark',
                detail: 'Can this phone recognise the imam without the computer? A test, not a feature.',
                trailing: Icon(Icons.chevron_right, color: c.inkSecondary),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AsrBenchScreen())),
              ),
            ],
          ),
          RubricGroup(
            label: 'About',
            children: [
              Padding(
                padding: const EdgeInsets.all(RubricSpace.s4),
                child: Text(
                  'Rafiq al-Tarawih follows the imam and shows the current surah and ayah.\n\n'
                  'Quran text: Tanzil Project (tanzil.net), Uthmani and Simple Clean v1.1, CC BY 3.0.\n'
                  'Fonts: Amiri Quran, Amiri, Newsreader, IBM Plex Sans and IBM Plex Sans Arabic, '
                  'SIL Open Font License 1.1.\n'
                  'Speech model: Tarteel whisper-base-ar-quran, Apache 2.0.\n'
                  'On-device runtime: sherpa-onnx (k2-fsa), Apache 2.0.',
                  style: caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String appearanceLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.dark => 'Dark',
      ThemeMode.light => 'Light',
      ThemeMode.system => 'System',
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
    return Scaffold(
      appBar: AppBar(title: const Text('Quran text size')),
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
              Text('Size', style: RubricText.label.copyWith(color: c.ink)),
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
          Text('The ayah numbers and line spacing scale with the text.',
              style: RubricText.caption.copyWith(color: c.inkSecondary)),
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
    final (icon, color, text) = !health.reachable
        ? (Icons.wifi_off_outlined, c.signal, health.error ?? 'Failed')
        : health.asr
            ? (
                Icons.check,
                c.ink,
                'Connected · ${health.latency!.inMilliseconds} ms · speech model ${health.device ?? 'ready on first use'}'
              )
            : (
                Icons.info_outline,
                c.signal,
                'Connected · ${health.latency!.inMilliseconds} ms · speech recognition NOT installed'
              );
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
