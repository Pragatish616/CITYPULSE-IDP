// Prints load and query timings for the map pack and routing engine, using
// the real Chennai pack. Run from packages/pulse_router:
//   dart run tool/engine_bench.dart [../../data/packs/2026-10-02]
//
// Numbers are for the machine it runs on. They are NOT phone numbers and must
// not be quoted as such (PLAN.md M0.9 / M4.9 measure the target device).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';

ByteData _read(String dir, String name) =>
    ByteData.sublistView(File('$dir/$name').readAsBytesSync());

void main(List<String> args) {
  final dir = args.isEmpty ? '../../data/packs/2026-10-02' : args.first;
  final sw = Stopwatch()..start();
  final graph = _read(dir, 'graph.bin');
  final nodes = _read(dir, 'nodes.bin');
  final meta = _read(dir, 'meta.bin');
  final readMs = sw.elapsedMilliseconds;

  sw
    ..reset()
    ..start();
  final pack = MapPack.parse(graph: graph, nodes: nodes, meta: meta);
  final parseMs = sw.elapsedMilliseconds;

  sw
    ..reset()
    ..start();
  final engine = RoutingEngine(
    pack: pack,
    hazardClasses: const {
      'flood': HazardClassParams(
        decayTauSeconds: 7200,
        severity: 1,
        hMaxMm: 300,
        epsilon: 0.1,
      ),
    },
    userClasses: const {
      'commuter': UserClassParams(z: 0, lambda: 0.3),
      'emergency': UserClassParams(z: 2, lambda: 1),
    },
    sourceReliability: const {'crowd': 0.6},
  );
  final engineMs = sw.elapsedMilliseconds;

  final rng = math.Random(7);
  final times = <double>[];
  var found = 0;
  var detours = 0;
  var penaltySeconds = 0.0;
  var attempts = 0;
  final at = DateTime.utc(2026, 10, 2, 6);
  while (times.length < 60 && attempts < 400) {
    attempts++;
    final a = rng.nextInt(pack.nodeCount);
    final b = rng.nextInt(pack.nodeCount);
    final outcome = engine.route(
      fromLat: pack.nodeLat[a],
      fromLon: pack.nodeLon[a],
      toLat: pack.nodeLat[b],
      toLon: pack.nodeLon[b],
      userClass: attempts.isEven ? 'emergency' : 'commuter',
      at: at,
    );
    if (outcome is RouteFound) {
      found++;
      times.add(outcome.plan.computeMilliseconds);
      if (outcome.plan.detours) detours++;
      penaltySeconds += outcome.plan.trace.chosen.hazardTimePenaltySeconds;
    }
  }
  times.sort();
  double pct(double p) => times[((times.length - 1) * p).round()];

  final risk = engine.riskEdges(at: at).length;
  stdout
    ..writeln('pack files read      : $readMs ms')
    ..writeln('MapPack.parse (+CSR) : $parseMs ms')
    ..writeln('engine + snap index  : $engineMs ms')
    ..writeln('routes found         : $found of $attempts random pairs')
    ..writeln(
      'route compute ms     : p50 ${pct(0.5).toStringAsFixed(1)}  '
      'p90 ${pct(0.9).toStringAsFixed(1)}  max ${times.last.toStringAsFixed(1)}',
    )
    ..writeln('routes that detour   : $detours (mean hazard penalty '
        '${(penaltySeconds / found).toStringAsFixed(1)} s)')
    ..writeln('hazard-map edges     : $risk (prior set, event state active)');
}
