/// The app root: theme, router, and the ADR-011 disclaimer gate.
///
/// `MaterialApp.router` -> [DisclaimerGate] -> the router's navigator. Nothing
/// in the app is reachable until the disclaimer for the running version has
/// been acknowledged, including deep links.
library;

import 'dart:async';

import 'package:citypulse_app/src/app_router.dart';
import 'package:citypulse_app/src/core/theme.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_gate.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_store.dart';
import 'package:citypulse_app/src/features/report/report_repository.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The root widget. [appVersion] and [disclaimerStore] are injectable so tests
/// never depend on the real `package_info_plus` / `shared_preferences`
/// platform channels. [router] is injectable for tests that start elsewhere.
class CityPulseApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const CityPulseApp({
    required this.appVersion,
    required this.disclaimerStore,
    this.router,
    super.key,
  });

  /// The running app's version string; ADR-011 re-shows the disclaimer
  /// whenever it changes.
  final String appVersion;

  /// Where ADR-011 acknowledgement is persisted.
  final DisclaimerStore disclaimerStore;

  /// A router to use instead of the default.
  final GoRouter? router;

  @override
  ConsumerState<CityPulseApp> createState() => _CityPulseAppState();
}

class _CityPulseAppState extends ConsumerState<CityPulseApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = widget.router ?? buildRouter();
  Timer? _flushTimer;

  @override
  void initState() {
    super.initState();
    // Send reports that were queued while offline: at start, every minute, and
    // whenever the app comes back to the foreground (a phone pauses timers in
    // the background, and returning to signal is when the queue can empty).
    WidgetsBinding.instance
      ..addObserver(this)
      ..addPostFrameCallback((_) => unawaited(_flush()));
    _flushTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_flush()),
    );
  }

  Future<void> _flush() async {
    try {
      final ReportRepository repo = ref.read(reportRepositoryProvider);
      if (repo.pendingCount > 0) await repo.flushQueue();
      // Offline is the normal case this guards against.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CityPulse',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: _router,
      builder: (context, child) => DisclaimerGate(
        appVersion: widget.appVersion,
        store: widget.disclaimerStore,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
