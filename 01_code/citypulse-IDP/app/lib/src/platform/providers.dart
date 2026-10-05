/// Dependency wiring (Riverpod). Everything the UI depends on that touches the
/// outside world -- the network, the asset bundle, the clock, the routing
/// engine -- is a provider here, so tests replace them with fakes.
library;

import 'dart:async';
import 'dart:convert';

import 'package:citypulse_app/src/core/app_config.dart';
import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/domain/rain_status.dart';
import 'package:citypulse_app/src/features/report/report_repository.dart';
import 'package:citypulse_app/src/platform/in_process_backend.dart';
import 'package:citypulse_app/src/platform/observation_puller.dart';
import 'package:citypulse_app/src/platform/router_api_backend.dart';
import 'package:citypulse_app/src/platform/routing_backend.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pulse_router/pulse_router.dart';

/// Build-time configuration.
final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig());

/// The shared HTTP client.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Where the bundled assets come from.
final assetBundleProvider = Provider<AssetBundle>((ref) => rootBundle);

/// The wall clock (UTC); overridden in tests.
final clockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// Which side actually calculates, after resolving [ComputeMode.auto].
final computeSiteProvider = Provider<ComputeSite>((ref) {
  final mode = ref.watch(settingsProvider.select((s) => s.compute));
  return switch (mode) {
    ComputeMode.device => ComputeSite.device,
    ComputeMode.server => ComputeSite.server,
    // A browser should not hold the city graph; a phone should work offline.
    ComputeMode.auto => kIsWeb ? ComputeSite.server : ComputeSite.device,
  };
});

/// The routing back end for the current settings.
final routingBackendProvider = Provider<RoutingBackend>((ref) {
  final config = ref.watch(appConfigProvider);
  final client = ref.watch(httpClientProvider);
  final RoutingBackend backend;
  if (ref.watch(computeSiteProvider) == ComputeSite.server) {
    backend = RouterApiBackend(baseUrl: config.routerApiUrl, client: client);
  } else {
    backend = InProcessBackend(
      bundle: ref.watch(assetBundleProvider),
      clock: ref.watch(clockProvider),
      pullObservations: ObservationPuller(
        ingestUrl: config.ingestUrl,
        client: client,
      ).pull,
      pullEventState: () async {
        final r = await client
            .get(AppConfig.join(config.routerApiUrl, 'event-state'))
            .timeout(const Duration(seconds: 5));
        final state =
            (jsonDecode(r.body) as Map<String, Object?>)['event_state']!
                as String;
        return EventState.parse(state);
      },
    );
  }
  ref.onDispose(backend.dispose);
  return backend;
});

/// Completes when the routing back end can answer.
final backendReadyProvider = FutureProvider<void>(
  (ref) => ref.watch(routingBackendProvider).warmUp(),
);

/// The current flood-event state, for the banner.
final eventStateProvider = FutureProvider<EventState>((ref) async {
  await ref.watch(backendReadyProvider.future);
  return ref.watch(routingBackendProvider).eventState();
});

/// Satellite rain over the city and why the event state is what it is, from the router service's `GET /event-state` (ADR-027).
///
/// `null` when the service cannot be reached or answers something unusable (a phone with no network, a service that predates the
/// rain feed). That is "unknown", never "no rain": the banner shows nothing in that case. Refreshes itself every five minutes.
final rainStatusProvider = FutureProvider<RainStatus?>((ref) async {
  final config = ref.watch(appConfigProvider);
  final client = ref.watch(httpClientProvider);
  final timer = Timer(const Duration(minutes: 5), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    final r = await client
        .get(AppConfig.join(config.routerApiUrl, 'event-state'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    return RainStatus.tryParse(jsonDecode(r.body));
  } on Object {
    return null;
  }
});

/// Bumped when something that changes the hazard picture arrives (a report), so the map fetches the
/// overlay for the area in view again. The overlay itself is fetched per visible area, never whole
/// (ADR-020): see `MapScreen`.
class RiskRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// Marks the overlay stale.
  void bump() => state++;
}

/// See [RiskRevision].
final riskRevisionProvider = NotifierProvider<RiskRevision, int>(
  RiskRevision.new,
);

/// Sends and queues reports.
final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = ReportRepository(
    ingestUrl: ref.watch(appConfigProvider).ingestUrl,
    prefs: prefs,
    installId: () => InstallId.read(prefs),
    client: ref.watch(httpClientProvider),
    clock: ref.watch(clockProvider),
    onAccepted: (o) {
      ref.read(routingBackendProvider).addLocalObservation(o);
      ref.read(riskRevisionProvider.notifier).bump();
    },
  );
  return repo;
});
