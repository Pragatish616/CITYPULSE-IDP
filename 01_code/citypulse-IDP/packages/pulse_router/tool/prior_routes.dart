// Routes the same seeded node pairs under several packs that differ only in their per-edge flood prior (ADR-026 part C).
//
//   dart run tool/prior_routes.dart OUT.json PAIRS SEED label=packDir [label=packDir ...]
//
// For every pair and every pack it asks the engine for a route in an active flood event, for the commuter and pedestrian
// classes (ROUTE_CLASSES, default commuter,pedestrian; HAZARD_CONFIG may name another config file), and records the polyline and the distances. Scoring against a flood extent happens in Python
// (scripts/sus_router_eval.py). All packs must share one graph (same nodes and edges); only meta.bin's prior differs.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:yaml/yaml.dart';

ByteData _read(String dir, String name) =>
    ByteData.sublistView(File('$dir/$name').readAsBytesSync());

void main(List<String> args) {
  if (args.length < 4) {
    stderr.writeln('usage: prior_routes OUT.json PAIRS SEED label=packDir ...');
    exit(2);
  }
  final out = args[0];
  final pairs = int.parse(args[1]);
  final seed = int.parse(args[2]);
  final variants = <String, MapPack>{};
  for (final a in args.skip(3)) {
    final i = a.indexOf('=');
    final dir = a.substring(i + 1);
    variants[a.substring(0, i)] = MapPack.parse(
      graph: _read(dir, 'graph.bin'),
      nodes: _read(dir, 'nodes.bin'),
      meta: _read(dir, 'meta.bin'),
    );
  }
  final first = variants.values.first;
  for (final p in variants.values) {
    if (p.nodeCount != first.nodeCount || p.edgeCount != first.edgeCount) {
      stderr.writeln('packs do not share one graph');
      exit(2);
    }
  }
  final config = EngineConfig.fromMap(
    (loadYaml(File(Platform.environment['HAZARD_CONFIG'] ?? '../../config/hazard_classes.yaml').readAsStringSync()) as YamlMap)
        .cast<Object?, Object?>(),
  );
  final at = DateTime.utc(2026, 10, 3, 6);
  final engines = {
    for (final e in variants.entries)
      e.key: RoutingEngine(
        pack: e.value,
        hazardClasses: config.hazardClasses,
        userClasses: config.userClasses,
        sourceReliability: config.sourceReliability,
        travelProfiles: config.travelProfiles,
        eventState: EventState.active,
      ),
  };
  final classes = (Platform.environment['ROUTE_CLASSES'] ?? 'commuter,pedestrian').split(',');
  final rng = math.Random(seed);
  final rows = <Map<String, Object?>>[];
  var skipped = 0;
  for (var i = 0; i < pairs; i++) {
    final a = rng.nextInt(first.nodeCount);
    final b = rng.nextInt(first.nodeCount);
    final row = <String, Object?>{'pair': i, 'from': a, 'to': b, 'routes': <String, Object?>{}};
    var ok = true;
    for (final eng in engines.entries) {
      for (final c in classes) {
        final o = eng.value.route(
          fromLat: first.nodeLat[a],
          fromLon: first.nodeLon[a],
          toLat: first.nodeLat[b],
          toLon: first.nodeLon[b],
          userClass: c,
          at: at,
          queryId: 'pr-$i',
        );
        if (o is! RouteFound) {
          ok = false;
          continue;
        }
        final ch = o.plan.trace.chosen;
        (row['routes']! as Map<String, Object?>)['${eng.key}|$c'] = {
          'distance_m': ch.distanceMeters,
          'duration_s': ch.durationSeconds,
          'free_flow_s': ch.freeFlowDurationSeconds,
          'worst_edge_p': ch.worstEdgeP,
          'path': [
            for (final p in o.plan.path) [double.parse(p.lat.toStringAsFixed(5)), double.parse(p.lon.toStringAsFixed(5))],
          ],
        };
      }
    }
    if (ok && (row['routes']! as Map).length == engines.length * classes.length) {
      rows.add(row);
    } else {
      skipped++;
    }
  }
  File(out).writeAsStringSync(jsonEncode({
    'seed': seed,
    'pairs_requested': pairs,
    'pairs_with_all_routes': rows.length,
    'pairs_skipped': skipped,
    'variants': variants.keys.toList(),
    'classes': classes,
    'rows': rows,
  }));
  stdout.writeln('wrote $out: ${rows.length} pairs, $skipped skipped');
}
