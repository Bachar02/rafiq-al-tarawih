import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/recognition/endpoint.dart';
import '../../services/server_health.dart';

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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Section('Recognition server'),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Server address',
              hintText: '192.168.1.5:8765',
              errorText: _addressError,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveAddress(),
            onEditingComplete: _saveAddress,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check_rounded),
                label: const Text('Test connection'),
              ),
              const SizedBox(width: 12),
              if (_health != null) Expanded(child: _HealthText(_health!)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Start the server on your laptop with:  python -m rafiq_server --host 0.0.0.0\n'
            'then enter the laptop\'s Wi-Fi address and port. On the Android emulator, use 10.0.2.2:8765.',
            style: context.text.bodySmall?.copyWith(color: context.colors.muted),
          ),
          const _Section('While listening'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep the screen on'),
            subtitle: const Text('Recommended during prayer'),
            value: settings.keepScreenOn,
            onChanged: (v) => update((s) => s.copyWith(keepScreenOn: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show diagnostics'),
            subtitle: const Text('What the speech model hears, for testing'),
            value: settings.showDiagnostics,
            onChanged: (v) => update((s) => s.copyWith(showDiagnostics: v)),
          ),
          const _Section('Display'),
          Text('Quran text size', style: context.text.bodyLarge),
          Slider(
            value: settings.textScale,
            min: 0.8,
            max: 1.6,
            divisions: 8,
            label: '${(settings.textScale * 100).round()}%',
            onChanged: (v) => update((s) => s.copyWith(textScale: v)),
          ),
          Text(
            'وَأَقِيمُوا وُجُوهَكُمْ عِندَ كُلِّ مَسْجِدٍ',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(fontFamily: quranFont, fontSize: 26 * settings.textScale, height: 2),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (v) => update((s) => s.copyWith(themeMode: v.first)),
          ),
          const _Section('About'),
          Text(
            'Rafiq al-Tarawih follows the imam and shows the current surah and ayah.\n\n'
            'Quran text: Tanzil Project (tanzil.net), Simple Clean v1.1, CC BY 3.0.\n'
            'Font: Amiri Quran, SIL Open Font License 1.1.\n'
            'Speech model: Tarteel whisper-base-ar-quran, Apache 2.0 (runs on the server).',
            style: context.text.bodySmall?.copyWith(color: context.colors.muted),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: context.text.labelMedium?.copyWith(color: context.colors.muted, letterSpacing: 0.8),
        ),
      );
}

class _HealthText extends StatelessWidget {
  const _HealthText(this.health);
  final ServerHealth health;

  @override
  Widget build(BuildContext context) {
    if (!health.reachable) {
      return Text(health.error ?? 'Failed', style: context.text.bodySmall?.copyWith(color: context.colors.lost));
    }
    final ms = health.latency!.inMilliseconds;
    final asr =
        health.asr ? 'speech model ${health.device ?? 'ready on first use'}' : 'speech recognition NOT installed';
    return Text(
      'Connected · $ms ms · $asr',
      style: context.text.bodySmall?.copyWith(color: health.asr ? context.colors.following : context.colors.uncertain),
    );
  }
}
