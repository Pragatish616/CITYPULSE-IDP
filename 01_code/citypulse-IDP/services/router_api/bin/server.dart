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

import 'dart:io';

import 'package:router_api/router_api.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final s = bootstrapRouter(Platform.environment);
  final server = await io.serve(s.handler, InternetAddress.anyIPv4, s.port);
  stdout.writeln(
    'router_api listening on :${server.port} for ${s.city.id} '
    '(${s.engine.pack.edgeCount} edges'
    '${s.details.map((d) => ', ${d.city.id} ${d.engine.pack.edgeCount} edges').join()}, '
    'event state ${s.reportEngine.eventState.name}, ${s.events.status().mode} mode)',
  );
}
