import 'dart:io';

// Shared fakes for widget and unit tests: a scripted routing back end, a fake
// map that records what the screens ask of it, and a pumped app.
import 'package:citypulse_app/src/app.dart';
import 'package:citypulse_app/src/core/city.dart';
import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_store.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/domain/rain_status.dart';
import 'package:citypulse_app/src/features/map/map_screen.dart'
    show watchlistGeoJsonProvider;
import 'package:citypulse_app/src/features/map/map_surface.dart';
import 'package:citypulse_app/src/features/map/route_card.dart'
    show hazardNounsProvider;
import 'package:citypulse_app/src/features/report/report_repository.dart';
import 'package:citypulse_app/src/features/settings/settings_screen.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:citypulse_app/src/platform/routing_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime kTestNow = DateTime.utc(2026, 10, 2, 6);

/// Two watchlist pins, as the real provider would return them.
const String kWatchlistFixture =
    '{"type":"FeatureCollection","features":['
    '{"type":"Feature","geometry":{"type":"Point","coordinates":[80.2,12.9]},"properties":{"id":"tw1-0001","verified":false}},'
    '{"type":"Feature","geometry":{"type":"Point","coordinates":[80.3,13.1]},"properties":{"id":"tw1-0002","verified":false}}'
    ']}';

/// A trace like `docs/CONTRACTS.md` §3's worked example: Route A is 2 minutes
/// slower than Route B and avoids a reported flood.
DecisionTrace sampleTrace({
  ConfidenceBand band = ConfidenceBand.moderate,
  bool withAlternative = true,
  List<DataGap> dataGaps = const [],
}) => DecisionTrace(
  queryId: 'test',
  computedAt: kTestNow,
  mode: RoutingMode.offline,
  userClass: UserClass.commuter,
  z: 0,
  lambda: 0.3,
  chosen: ChosenRoute(
    routeId: 'A',
    durationSeconds: 1147,
    distanceMeters: 8420,
    freeFlowDurationSeconds: 1023,
    worstEdgeP: 0.31,
    geometryRef: 'nodes:1,2,3',
  ),
  alternatives: withAlternative
      ? const [
          AlternativeRoute(
            routeId: 'B',
            durationSeconds: 907,
            rejectedBecause: RejectedBecause.chanceConstraint,
            blockingEdges: [
              BlockingEdge(
                edgeId: 184223,
                streetName: 'Kotturpuram Bridge approach',
                hazardClass: 'flood',
                pMean: 0.792,
                pPessimistic: 1,
                nEff: 1.8,
                newestObservationAgeSeconds: 179,
                sourceClass: 'crowd',
                depthMm: 320,
                timePenaltySeconds: 0,
                removedByChanceConstraint: true,
              ),
            ],
          ),
        ]
      : const [],
  contextFacts: const [],
  dataGaps: dataGaps,
  confidenceBand: band,
);

RouteView sampleRoute({
  ConfidenceBand band = ConfidenceBand.moderate,
  bool withAlternative = true,
  List<DataGap> dataGaps = const [],
  ComputeSite site = ComputeSite.device,
  bool? hazardLayer,
}) => RouteView(
  trace: sampleTrace(
    band: band,
    withAlternative: withAlternative,
    dataGaps: dataGaps,
  ),
  path: const [(lat: 13.04, lon: 80.23), (lat: 13.0, lon: 80.22)],
  fastestPath: const [(lat: 13.04, lon: 80.23), (lat: 13.01, lon: 80.24)],
  detours: withAlternative,
  avoidedHazards: withAlternative
      ? const [(lat: 13.02, lon: 80.235)]
      : const [],
  eventState: EventState.active,
  computeMilliseconds: 12,
  computedOn: site,
  origin: (lat: 13.04, lon: 80.23),
  destination: (lat: 13.0, lon: 80.22),
  hazardLayer: hazardLayer,
);

/// A routing back end whose answers a test scripts.
class FakeBackend implements RoutingBackend {
  FakeBackend({
    this.site = ComputeSite.device,
    this.state = EventState.active,
    RouteView? route,
  }) : routeResult = route ?? sampleRoute();

  @override
  ComputeSite site;
  EventState state;
  RouteView routeResult;
  RoutingException? routeError;
  Duration routeDelay = Duration.zero;
  List<Place> places = const [
    Place(name: 'Usman Road', point: (lat: 13.04, lon: 80.23)),
    Place(name: 'Velachery Main Road', point: (lat: 12.98, lon: 80.22)),
  ];
  String risk = '{"type":"FeatureCollection","features":[]}';
  final routeCalls = <({GeoPoint from, GeoPoint to, TravelType travel})>[];
  final searched = <String>[];
  final observations = <EngineObservation>[];
  var warmUps = 0;

  @override
  Future<void> warmUp() async => warmUps++;

  @override
  Future<RouteView> route({
    required GeoPoint from,
    required GeoPoint to,
    required TravelType travel,
    DateTime? at,
  }) async {
    routeCalls.add((from: from, to: to, travel: travel));
    if (routeDelay > Duration.zero) await Future<void>.delayed(routeDelay);
    final error = routeError;
    if (error != null) throw error;
    return routeResult;
  }

  @override
  Future<String> riskGeoJson({
    required TravelType travel,
    GeoBounds? bounds,
  }) async {
    riskRequests.add(bounds);
    return risk;
  }

  /// Every overlay request the app made, in order (null = whole map).
  final riskRequests = <GeoBounds?>[];

  @override
  Future<List<Place>> searchPlaces(String query, {GeoPoint? near}) async {
    searched.add(query);
    return [
      for (final p in places)
        if (p.name.toLowerCase().contains(query.toLowerCase().trim())) p,
    ];
  }

  @override
  Future<EventState> eventState() async => state;

  @override
  void addLocalObservation(EngineObservation observation) =>
      observations.add(observation);

  @override
  void dispose() {}
}

/// Records every request the screens make of the map.
class FakeMapHandle implements MapHandle {
  String? risk;
  String? watchlist;
  List<GeoPoint>? path;
  List<GeoPoint>? fastest;
  List<MapMarker> markers = const [];
  final fits = <List<GeoPoint>>[];
  final riskCalls = <String?>[];
  GeoPoint centre = (lat: 13.05, lon: 80.25);

  /// What the map reports it is showing: a Chennai neighbourhood at zoom 12 unless a test moves it.
  MapView currentView = (
    bounds: (minLat: 13.00, minLon: 80.20, maxLat: 13.10, maxLon: 80.30),
    zoom: 12.0,
  );

  @override
  Future<MapView?> view() async => currentView;

  @override
  GeoPoint? cameraCenter() => centre;

  @override
  Future<void> fit(List<GeoPoint> points) async => fits.add(points);

  @override
  Future<void> flyTo(GeoPoint point, {double zoom = 15}) async {}

  @override
  Future<void> setRisk(String? geoJson) async {
    risk = geoJson;
    riskCalls.add(geoJson);
  }

  @override
  Future<void> setRoute({
    List<GeoPoint>? path,
    List<GeoPoint>? fastest,
    List<MapMarker> markers = const [],
  }) async {
    this.path = path;
    this.fastest = fastest;
    this.markers = markers;
  }

  @override
  Future<void> setWatchlist(String? geoJson) async => watchlist = geoJson;
}

/// Everything a test needs to drive the app.
class AppHarness {
  AppHarness({
    FakeBackend? backend,
    http.Client? ingest,
    this.disclaimerAccepted = true,
    this.city,
    this.detailCities = const [],
    this.rainStatus,
  }) : backend = backend ?? FakeBackend(),
       ingest = ingest ?? MockClient((_) async => http.Response('{}', 201));

  final FakeBackend backend;
  final http.Client ingest;
  final bool disclaimerAccepted;

  /// The city to run in; the real Chennai entry when null.
  final CityConfig? city;

  /// Detailed cities served inside the region (ADR-022).
  final List<CityConfig> detailCities;

  /// What the router service says about satellite rain (ADR-027). Null, as in a real unreachable service, shows no rain line.
  final RainStatus? rainStatus;
  final map = FakeMapHandle();
  late MapSurfaceCallbacks mapCallbacks;
  late SharedPreferences prefs;
  late ProviderContainer container;

  /// Pumps the app at [size] logical pixels.
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(420, 900),
    Map<String, Object> prefsValues = const {},
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
    final store = InMemoryDisclaimerStore();
    if (disclaimerAccepted) await store.acknowledge('1.0.0');

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cityProvider.overrideWithValue(city ?? testCity()),
        detailCitiesProvider.overrideWithValue(detailCities),
        appVersionProvider.overrideWithValue('1.0.0'),
        clockProvider.overrideWithValue(() => kTestNow),
        routingBackendProvider.overrideWithValue(backend),
        // No real HTTP and no five-minute refresh timer under the widget tester.
        rainStatusProvider.overrideWith((ref) async => rainStatus),
        reportRepositoryProvider.overrideWith(
          (ref) => ReportRepository(
            ingestUrl: 'http://ingest.test',
            prefs: prefs,
            installId: () => InstallId.read(prefs),
            client: ingest,
            clock: () => kTestNow,
            onAccepted: backend.addLocalObservation,
          ),
        ),
        // Asset-backed providers are replaced by fixtures here: real asset I/O
        // does not complete under the widget tester's fake clock. The real
        // bundled data is checked in test/data/bundled_assets_test.dart.
        hazardNounsProvider.overrideWith(
          (ref) async => const {
            'flood': 'flooding',
            'waterlogging': 'waterlogging',
            'debris': 'debris on the road',
          },
        ),
        watchlistGeoJsonProvider.overrideWith((ref) async => kWatchlistFixture),
        mapSurfaceBuilderProvider.overrideWithValue((context, callbacks) {
          mapCallbacks = callbacks;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => callbacks.onReady(map),
          );
          return const SizedBox.expand(key: Key('fake-map'));
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CityPulseApp(appVersion: '1.0.0', disclaimerStore: store),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// The city the widget tests run in: the real Chennai entry of `config/cities.yaml`, so the texts the
/// tests see are the ones users see.
CityConfig testCity([String id = 'chennai']) => CityConfig.fromMap(
  (loadYaml(File('../config/cities.yaml').readAsStringSync()) as YamlMap)
      .cast<Object?, Object?>(),
  id,
);

/// A made-up city with no flood-hazard layer and no local contact, for tests of the
/// "any city" behaviour. Not a real place.
CityConfig noHazardCity() => CityConfig.fromMap(
  (loadYaml('''
default_city: testville
cities:
  testville:
    name: { en: Testville, ta: டெஸ்ட்வில் }
    centre: { lat: 20.010, lon: 78.010 }
    bbox: { min_lat: 19.99, max_lat: 20.03, min_lon: 77.99, max_lon: 78.03 }
    pack: data/packs/testville
    hazard_layer: false
''') as YamlMap).cast<Object?, Object?>(),
  'testville',
);
