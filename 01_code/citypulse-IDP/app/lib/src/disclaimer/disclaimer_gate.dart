/// Gates access to the rest of the app behind the ADR-011 first-use
/// disclaimer. `docs/DECISIONS.md` ADR-011: shown "before first use, and
/// once per app version thereafter" -- this widget does not build its
/// `child` at all until the current `appVersion` has been acknowledged, so
/// there is no way to reach the route screen around it (a real gate, not a
/// dismiss-and-forget banner).
library;

import 'dart:async';

import 'package:citypulse_app/src/disclaimer/disclaimer_store.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_text.dart';
import 'package:flutter/material.dart';

/// Wraps [child], blocking on the ADR-011 disclaimer for [appVersion].
class DisclaimerGate extends StatefulWidget {
  /// Creates the gate. [store] defaults to the real
  /// `shared_preferences`-backed store; tests inject
  /// [InMemoryDisclaimerStore].
  const DisclaimerGate({
    required this.appVersion,
    required this.store,
    required this.child,
    super.key,
  });

  /// The current app version -- ADR-011 re-shows the disclaimer whenever
  /// this changes, so it must come from the real package version, not a
  /// constant.
  final String appVersion;

  /// Where acknowledgement is persisted.
  final DisclaimerStore store;

  /// The rest of the app, built only once acknowledged.
  final Widget child;

  @override
  State<DisclaimerGate> createState() => _DisclaimerGateState();
}

class _DisclaimerGateState extends State<DisclaimerGate> {
  // null while the store hasn't answered yet -- deliberately still gated
  // during that window rather than flashing the route screen first.
  bool? _acknowledged;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final acknowledged = await widget.store.isAcknowledged(widget.appVersion);
    if (mounted) setState(() => _acknowledged = acknowledged);
  }

  Future<void> _accept() async {
    await widget.store.acknowledge(widget.appVersion);
    if (mounted) setState(() => _acknowledged = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_acknowledged != true) {
      return _FirstUseDisclaimerScreen(onAcknowledge: _accept);
    }
    return widget.child;
  }
}

class _FirstUseDisclaimerScreen extends StatelessWidget {
  const _FirstUseDisclaimerScreen({required this.onAcknowledge});

  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.info_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  kFirstUseDisclaimer,
                  key: const Key('first-use-disclaimer-text'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  key: const Key('first-use-disclaimer-accept'),
                  onPressed: onAcknowledge,
                  child: const Text('I understand'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
