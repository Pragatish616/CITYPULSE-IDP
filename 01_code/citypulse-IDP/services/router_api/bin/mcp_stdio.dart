/// CityPulse as a Model Context Protocol server over stdio (C6). See `lib/src/mcp.dart` for the tools and the rules they keep.
///
///   dart run bin/mcp_stdio.dart            (from services/router_api)
///   dart compile exe bin/mcp_stdio.dart -o citypulse_mcp.exe
///
/// Same environment variables as `bin/server.dart` (CITY, CITIES_CONFIG, PACK_DIR, HAZARD_CONFIG, EVENT_STATE, OBSERVATIONS_URL...).
/// Relative defaults assume the working directory is services/router_api; MCP clients that start the server elsewhere should set
/// CITIES_CONFIG and HAZARD_CONFIG to absolute paths (see docs/MCP.md). stdout carries only protocol messages; logs go to stderr.
library;

import 'dart:convert';
import 'dart:io';

import 'package:router_api/router_api.dart';

Future<void> main() async {
  final env = Platform.environment;
  final hasReports = (env['OBSERVATIONS_URL'] ?? '').isNotEmpty;
  final s = bootstrapRouter(env, startSync: hasReports, accessLog: stderr.writeln);
  final mcp = McpServer(api: s.handler, hazardNouns: s.config.displayNouns);
  stderr.writeln('citypulse MCP server ready for ${s.city.id} (${s.engine.pack.edgeCount} edges)');
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      stdout.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error'},
      }));
      continue;
    }
    final response = await mcp.handle(message);
    if (response != null) stdout.writeln(jsonEncode(response));
  }
}
