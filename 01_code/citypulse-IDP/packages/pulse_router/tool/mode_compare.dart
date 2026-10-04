// Compares the four travel modes on the real Chennai pack (ADR-019): how often
// each mode's route differs from the car route, and what speeds and durations
// each gets. Seeded and deterministic; writes a result.json.
//
//   dart run tool/mode_compare.dart [outDir]
//
// Default outDir: ../../data/results/2026-10-03-travel-modes
//
// These are model outputs under placeholder profile assumptions
// (config/hazard_classes.yaml `travel_profiles`), not measurements of real
// travel. Desktop timings only.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:yaml/yaml.dart';

const seed = 20261003;
const pairs = 300;
const modes = ['commuter', 'pedestrian', 'cyclist', 'emergency'];

ByteData _read(String dir, String name) =>
    ByteData.sublistView(File('$dir/$name').readAsBytesSync());

double _median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

bool _samePath(List<GeoPoint> a, List<GeoPoint> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].lat != b[i].lat || a[i].lon != b[i].lon) return false;
  }
  return true;
}

void main(List<String> args) {
  final out = args.isEmpty ? '../../data/results/2026-10-03-travel-modes' : args.first;
  const packDir = '../../data/packs/2026-10-02';
  final pack = MapPack.parse(
    graph: _read(packDir, 'graph.bin'),
    nodes: _read(packDir, 'nodes.bin'),
    meta: _read(packDir, 'meta.bin'),
  );
  final config = EngineConfig.fromMap(
    (loadYaml(File('../../config/hazard_classes.yaml').readAsStringSync()) as YamlMap)
        .cast<Object?, Object?>(),
  );
  final at = DateTime.utc(2026, 10, 3, 6);

  final reports = <String, Object?>{};
  for (final state in [EventState.dry, EventState.active]) {
    final engine = RoutingEngine(
      pack: pack,
      hazardClasses: config.hazardClasses,
      userClasses: config.userClasses,
      sourceReliability: config.sourceReliability,
      travelProfiles: config.travelProfiles,
      eventState: state,
    );
    final rng = math.Random(seed);
    final found = {for (final m in modes) m: 0};
    final dist = {for (final m in modes) m: <double>[]};
    final secs = {for (final m in modes) m: <double>[]};
    final kmh = {for (final m in modes) m: <double>[]};
    final differs = {for (final m in modes) m: 0};
    final detours = {for (final m in modes) m: 0};
    var usable = 0;
    final swatch = Stopwatch()..start();
    for (var i = 0; i < pairs; i++) {
      final a = rng.nextInt(pack.nodeCount);
      final b = rng.nextInt(pack.nodeCount);
      final plans = <String, RoutePlan?>{};
      for (final m in modes) {
        final o = engine.route(
          fromLat: pack.nodeLat[a],
          fromLon: pack.nodeLon[a],
          toLat: pack.nodeLat[b],
          toLon: pack.nodeLon[b],
          userClass: m,
          at: at,
          queryId: 'cmp-$i',
        );
        plans[m] = o is RouteFound ? o.plan : null;
      }
      final car = plans['commuter'];
      if (car == null) continue;
      usable++;
      for (final m in modes) {
        final p = plans[m];
        if (p == null) continue;
        found[m] = found[m]! + 1;
        final metres = p.trace.chosen.distanceMeters;
        final s = p.trace.chosen.durationSeconds;
        dist[m]!.add(metres / 1000);
        secs[m]!.add(s / 60);
        kmh[m]!.add(metres / s * 3.6);
        if (p.detours) detours[m] = detours[m]! + 1;
        if (m != 'commuter' && !_samePath(p.path, car.path)) {
          differs[m] = differs[m]! + 1;
        }
      }
    }
    swatch.stop();
    reports[state.name] = {
      'pairs_with_a_car_route': usable,
      'seconds_total_all_modes': swatch.elapsedMilliseconds / 1000,
      'by_mode': {
        for (final m in modes)
          m: {
            'routes_found': found[m],
            'median_distance_km': _median(dist[m]!),
            'median_duration_min': _median(secs[m]!),
            'median_speed_kmh': _median(kmh[m]!),
            if (m != 'commuter') 'route_differs_from_car': differs[m],
            if (m != 'commuter')
              'share_differs_from_car':
                  found[m]! == 0 ? null : differs[m]! / found[m]!,
            'routes_with_hazard_detour': detours[m],
          },
      },
    };
    stdout.writeln('[${state.name}] $usable pairs');
    for (final m in modes) {
      final r = (reports[state.name]! as Map)['by_mode'] as Map;
      stdout.writeln('  $m: ${r[m]}');
    }
  }

  Directory(out).createSync(recursive: true);
  File('$out/result.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'task': 'ADR-019 travel modes on the Chennai pack',
      'seed': seed,
      'pairs_sampled': pairs,
      'pair_sampling': 'two uniformly random graph nodes per pair; pairs with no car route are skipped',
      'pack': packDir,
      'replay_clock': at.toIso8601String(),
      'caveat': 'Placeholder travel profiles (config/hazard_classes.yaml); model output, not measured travel. No reports loaded: only the static GCC prior.',
      'results_by_event_state': reports,
    }),
  );
  stdout.writeln('wrote $out/result.json');
}
