/// Builds the routing service from environment variables: the city's pack, places, engines, event state and the HTTP handler.
/// Shared by `bin/server.dart` (HTTP) and `bin/mcp_stdio.dart` (Model Context Protocol), so both serve exactly the same router.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:router_api/src/api.dart';
import 'package:router_api/src/event_state.dart';
import 'package:router_api/src/observation_sync.dart';
import 'package:router_api/src/rain_sync.dart';
import 'package:router_api/src/rewrite_proxy.dart';
import 'package:shelf/shelf.dart';
import 'package:yaml/yaml.dart';

ByteData _read(String dir, String name) =>
    ByteData.sublistView(File('$dir/$name').readAsBytesSync());

/// Everything a front end needs from a built router.
class RouterServices {
  /// Creates the bundle.
  RouterServices({
    required this.handler,
    required this.city,
    required this.engine,
    required this.details,
    required this.events,
    required this.reportEngine,
    required this.config,
    required this.port,
  });

  /// The HTTP API handler.
  final Handler handler;

  /// The served city.
  final CityConfig city;

  /// The main engine.
  final RoutingEngine engine;

  /// Detailed regions served inside the main one (ADR-022).
  final List<DetailRegion> details;

  /// The flood-event state controller.
  final EventStateController events;

  /// The engine that carries flood data.
  final RoutingEngine reportEngine;

  /// The hazard and travel configuration (display nouns included).
  final EngineConfig config;

  /// The port from `PORT` (default 8080).
  final int port;
}

/// Builds the router from [env]. With [startSync] false, no background pollers start (reports, rain, forecast).
RouterServices bootstrapRouter(
  Map<String, String> env, {
  bool startSync = true,
  void Function(String line)? accessLog,
}) {
  final citiesPath = env['CITIES_CONFIG'] ?? '../../config/cities.yaml';
  final citiesDoc = (loadYaml(File(citiesPath).readAsStringSync()) as YamlMap)
      .cast<Object?, Object?>();
  final city = CityConfig.fromMap(
    citiesDoc,
    env['CITY'] ?? CityConfig.defaultId(citiesDoc),
  );
  // The pack path in cities.yaml is relative to the repository root, which is the
  // parent of the config/ folder holding it.
  final repoRoot = File(citiesPath).absolute.parent.parent.path;
  final packDir = env['PACK_DIR'] ?? '$repoRoot/${city.packDir}';
  final configPath = env['HAZARD_CONFIG'] ?? '../../config/hazard_classes.yaml';
  final port = int.parse(env['PORT'] ?? '8080');

  final pack = MapPack.parse(
    graph: _read(packDir, 'graph.bin'),
    nodes: _read(packDir, 'nodes.bin'),
    meta: _read(packDir, 'meta.bin'),
  );
  // Named places (cities, towns, villages) for search, if the pack has them.
  final placesFile = File(
    city.placesFile == null
        ? '$packDir/places.json'
        : '$repoRoot/${city.placesFile}',
  );
  final gazetteer = placesFile.existsSync()
      ? parseGazetteer(placesFile.readAsStringSync())
      : const <GazetteerEntry>[];
  final manifest = File('$packDir/manifest.json');
  final built = manifest.existsSync()
      ? (jsonDecode(manifest.readAsStringSync()) as Map)['built'] as String
      : 'unknown';
  final config = EngineConfig.fromMap(
    loadYaml(File(configPath).readAsStringSync()) as YamlMap,
  );
  final engine = RoutingEngine(
    pack: pack,
    hazardClasses: config.hazardClasses,
    userClasses: config.userClasses,
    sourceReliability: config.sourceReliability,
    travelProfiles: config.travelProfiles,
    restrictionConfig: config.restrictions,
    eventState: EventState.parse(env['EVENT_STATE'] ?? 'active'),
  );

  // Detailed packs served inside this region (ADR-022), for example Chennai inside Tamil Nadu.
  final eventState = EventState.parse(env['EVENT_STATE'] ?? 'active');
  final details = <DetailRegion>[];
  for (final id in city.detailRegions) {
    final dc = CityConfig.fromMap(citiesDoc, id);
    final dir = '$repoRoot/${dc.packDir}';
    final dPack = MapPack.parse(
      graph: _read(dir, 'graph.bin'),
      nodes: _read(dir, 'nodes.bin'),
      meta: _read(dir, 'meta.bin'),
    );
    final dPlaces = File('$dir/places.json');
    details.add(
      DetailRegion(
        city: dc,
        engine: RoutingEngine(
          pack: dPack,
          hazardClasses: config.hazardClasses,
          userClasses: config.userClasses,
          sourceReliability: config.sourceReliability,
          travelProfiles: config.travelProfiles,
          restrictionConfig: config.restrictions,
          eventState: eventState,
        ),
        places: PlaceIndex(
          dPack,
          gazetteer: dPlaces.existsSync()
              ? parseGazetteer(dPlaces.readAsStringSync())
              : const <GazetteerEntry>[],
        ),
      ),
    );
  }

  // Reports belong to the engine that carries flood data.
  final reportEngine = city.hazardLayer || details.isEmpty
      ? engine
      : details.first.engine;
  final observationsUrl = env['OBSERVATIONS_URL'];
  if (observationsUrl != null && observationsUrl.isNotEmpty) {
    final sync = ObservationSync(
      engine: reportEngine,
      baseUrl: Uri.parse(
        observationsUrl.endsWith('/') ? observationsUrl : '$observationsUrl/',
      ),
    );
    if (startSync) sync.start();
  }

  // The event state follows satellite rain by default, with a human override (ADR-027). It needs the report server (which fetches
  // the rain from NASA), so it is off when OBSERVATIONS_URL is not set, and EVENT_AUTO=0 switches it off on purpose.
  final rainUrl = (env['EVENT_AUTO'] == '0') ? null : observationsUrl;
  final hasRainSource = rainUrl != null && rainUrl.isNotEmpty;
  // ADR-029: a rain forecast may raise dry to watch. Off unless EVENT_FORECAST=1, and only with the automatic rain rule.
  final hasForecastSource = hasRainSource && env['EVENT_FORECAST'] == '1';
  final events = EventStateController(
    configured: eventState,
    hasRainSource: hasRainSource,
    hasForecastSource: hasForecastSource,
    apply: (state) {
      engine.eventState = state;
      for (final d in details) {
        d.engine.eventState = state;
      }
    },
  );
  if (hasRainSource && startSync) {
    RainSync(
      baseUrl: Uri.parse(rainUrl.endsWith('/') ? rainUrl : '$rainUrl/'),
      controller: events,
    ).start();
  }
  if (hasForecastSource && startSync) {
    ForecastSync(
      baseUrl: Uri.parse(rainUrl.endsWith('/') ? rainUrl : '$rainUrl/'),
      controller: events,
    ).start();
  }

  final handler = buildHandler(
    engine,
    places: PlaceIndex(pack, gazetteer: gazetteer),
    details: details,
    config: ApiConfig(
      allowedOrigin: env['ALLOWED_ORIGIN'] ?? '*',
      adminToken: env['ADMIN_TOKEN'],
      packBuilt: built,
      cityId: city.id,
      cityName: city.name.en,
      maxSnapMetres: city.maxSnapMetres,
      hazardLayer: city.hazardLayer,
      trustForwardedFor: env['TRUST_FORWARDED_FOR'] == '1',
    ),
    events: events,
    rewrite: RewriteProxy(
      apiKey: env['GROQ_API_KEY'],
      model: env['GROQ_MODEL'] ?? 'llama-3.1-8b-instant',
    ),
    accessLog: accessLog,
  );
  return RouterServices(
    handler: handler,
    city: city,
    engine: engine,
    details: details,
    events: events,
    reportEngine: reportEngine,
    config: config,
    port: port,
  );
}
