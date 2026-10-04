/// Language, where routes are calculated, and the anonymous install code.
library;

import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app version shown in Settings; injected in `main`.
final appVersionProvider = Provider<String>((ref) => '0.0.0');

/// The settings screen.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final site = ref.watch(computeSiteProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(s(Msg.settingsTitle))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s(Msg.settingsLanguage), style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<AppLanguage>(
            key: const Key('language-selector'),
            showSelectedIcon: false,
            segments: [
              for (final l in AppLanguage.values)
                ButtonSegment(value: l, label: Text(l.nativeName)),
            ],
            selected: {settings.language},
            onSelectionChanged: (v) => notifier.setLanguage(v.first),
          ),
          const SizedBox(height: 24),
          Text(s(Msg.settingsCompute), style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ComputeMode>(
            key: const Key('compute-selector'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ComputeMode.auto,
                label: Text(s(Msg.computeAuto)),
              ),
              ButtonSegment(
                value: ComputeMode.device,
                label: Text(s(Msg.computeDevice)),
              ),
              ButtonSegment(
                value: ComputeMode.server,
                label: Text(s(Msg.computeServer)),
              ),
            ],
            selected: {settings.compute},
            onSelectionChanged: (v) => notifier.setCompute(v.first),
          ),
          const SizedBox(height: 8),
          Text(
            '${s(Msg.settingsComputedOn)}: '
            '${site.name == 'device' ? s(Msg.onDevice) : s(Msg.onServer)}',
            key: const Key('compute-site'),
            style: text.bodySmall,
          ),
          const SizedBox(height: 24),
          Text(s(Msg.settingsPrivacy), style: text.titleSmall),
          const SizedBox(height: 4),
          Text(s(Msg.reportPrivacy), style: text.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('reset-install-id'),
            icon: const Icon(Icons.refresh),
            label: Text(s(Msg.settingsResetId)),
            onPressed: () {
              InstallId.reset(ref.read(sharedPreferencesProvider));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s(Msg.settingsResetIdDone))),
              );
            },
          ),
          const SizedBox(height: 24),
          ListTile(
            key: const Key('data-sources'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.map_outlined),
            title: Text(s(Msg.settingsDataSources)),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(s(Msg.settingsDataSources)),
                content: SingleChildScrollView(
                  child: SelectableText(s(Msg.dataSourcesBody)),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(s(Msg.close)),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            key: const Key('software-licences'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(s(Msg.settingsLicences)),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'CityPulse AI',
              applicationVersion: ref.read(appVersionProvider),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${s(Msg.settingsVersion)} ${ref.watch(appVersionProvider)}',
            key: const Key('app-version'),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
