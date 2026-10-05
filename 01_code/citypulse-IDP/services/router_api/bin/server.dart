/// Entry point: `dart run bin/server.dart` (or `dart compile exe`).
///
/// Configuration is by environment variable, never by command-line secret:
///   CITY              city id from config/cities.yaml (default: its default_city)
///   CITIES_CONFIG     path to config/cities.yaml (default ../../config/cities.yaml)
///   PACK_DIR          pack folder; default is the city's `pack` in cities.yaml
///                     (graph.bin, nodes.bin, meta.bin, manifest.json)
///   HAZARD_CONFIG     path to config/hazard_classes.yaml
///   PORT              default 8080
///   EVENT_STATE       dry | watch | active   (default active)
///   OBSERVATIONS_URL  FastAPI server root to poll for reports (optional)
///   ALLOWED_ORIGIN    CORS origin (default *, development only)
///   ADMIN_TOKEN       enables PUT /event-state (unset = disabled)
///   GROQ_API_KEY      enables POST /rewrite, the Tier 2 explanation proxy (unset = off)
///   GROQ_MODEL        Groq model id (default llama-3.1-8b-instant)
///   TRUST_FORWARDED_FOR  1 when behind a reverse proxy that sets X-Forwarded-For
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:router_api/router_api.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:yaml/yaml.dart';

ByteData _read(String dir, String name) =>
    ByteData.sublistView(File('$dir/$name').readAsBytesSync());

Future<void> main() async {
  final env = Platform.environment;
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
    ObservationSync(
      engine: reportEngine,
      baseUrl: Uri.parse(
        observationsUrl.endsWith('/') ? observationsUrl : '$observationsUrl/',
      ),
    ).start();
  }

  // The event state follows satellite rain by default, with a human override (ADR-027). It needs the report server (which fetches
  // the rain from NASA), so it is off when OBSERVATIONS_URL is not set, and EVENT_AUTO=0 switches it off on purpose.
  final rainUrl = (env['EVENT_AUTO'] == '0') ? null : observationsUrl;
  final hasRainSource = rainUrl != null && rainUrl.isNotEmpty;
  final events = EventStateController(
    configured: eventState,
    hasRainSource: hasRainSource,
    apply: (state) {
      engine.eventState = state;
      for (final d in details) {
        d.engine.eventState = state;
      }
    },
  );
  if (hasRainSource) {
    RainSync(
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
  );
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'router_api listening on :${server.port} for ${city.id} '
    '(${pack.edgeCount} edges'
    '${details.map((d) => ', ${d.city.id} ${d.engine.pack.edgeCount} edges').join()}, '
    'event state ${reportEngine.eventState.name}, ${events.status().mode} mode)',
  );
}
