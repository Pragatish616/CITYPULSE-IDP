/// Plain statements of what CityPulse is, what it is built on, and what it
/// cannot do (ADR-011), plus the emergency numbers.
library;

import 'package:citypulse_app/src/core/city.dart';
import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The help and about screen.
class HelpScreen extends ConsumerWidget {
  /// Creates the screen.
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget section(String title, String body, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(body, key: key, style: text.bodyMedium),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(s(Msg.helpTitle))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s(Msg.helpEmergency),
                    key: const Key('help-emergency'),
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  if (ref.watch(cityProvider).localContact case final contact?)
                    Text(
                      contact.forLanguage(
                        s.language == AppLanguage.ta ? 'ta' : 'en',
                      ),
                      key: const Key('help-local-contact'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // ADR-011: the disclaimer is always one tap away, verbatim.
          section(
            s(Msg.appName),
            kFirstUseDisclaimer,
            key: const Key('help-disclaimer'),
          ),
          section(s(Msg.helpLimits), s(Msg.helpLimitsBody)),
          section(s(Msg.helpAboutData), s(Msg.helpAboutDataBody)),
        ],
      ),
    );
  }
}
