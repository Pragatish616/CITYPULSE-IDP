/// The Dart AOT CLI (T2.4): `pulse_router route --graph … --observations …
/// --source … --target … --at … --user-class … --z … --lambda …`, emitting
/// a `DecisionTrace` as JSON on stdout.
///
/// This is how the Python evaluation harness calls the *same* router code
/// the Flutter client runs — never a second implementation of the
/// algorithm, per `docs/DECISIONS.md` ADR-001. AOT-compile with:
/// `dart compile exe bin/pulse_router.dart -o pulse_router`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:pulse_router/src/cli_io.dart';

Future<void> main(List<String> arguments) async {
  final isBatch = arguments.isNotEmpty && arguments.first == 'route-batch';
  if (arguments.isEmpty || (arguments.first != 'route' && !isBatch)) {
    stderr.writeln(
      'Usage: pulse_router route --graph <path> --observations <path> '
      '--source <id> --target <id> --at <iso8601> '
      '--user-class <commuter|emergency|pedestrian> '
      '--z <double> --lambda <double> [--query-id <id>] '
      '[--mode <offline|online_enriched>]\n'
      '       pulse_router route-batch --graph <path> --observations <path> '
      '--pairs <file of "source target" lines> --at <iso8601> '
      '--user-class <...> --z <double> --lambda <double> '
      '[--query-id-prefix <id>]',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final parser = ArgParser()
    ..addOption('graph', mandatory: true)
    ..addOption('observations', mandatory: true)
    ..addOption('source', mandatory: !isBatch)
    ..addOption('target', mandatory: !isBatch)
    ..addOption('pairs', mandatory: isBatch)
    ..addOption('query-id-prefix', defaultsTo: 'batch')
    ..addOption('at', mandatory: true)
    ..addOption(
      'user-class',
      mandatory: true,
      allowed: ['commuter', 'emergency', 'pedestrian', 'cyclist'],
    )
    ..addOption('z', mandatory: true)
    ..addOption('lambda', mandatory: true)
    ..addOption('query-id', defaultsTo: 'cli-query')
    ..addOption(
      'mode',
      defaultsTo: 'offline',
      allowed: ['offline', 'online_enriched'],
    );

  final ArgResults args;
  try {
    args = parser.parse(arguments.skip(1).toList());
  } on FormatException catch (e) {
    stderr.writeln('Argument error: ${e.message}');
    exitCode = 64;
    return;
  }

  final graphFile = File(args.option('graph')!);
  final observationsFile = File(args.option('observations')!);
  if (!graphFile.existsSync()) {
    stderr.writeln('Graph file not found: ${graphFile.path}');
    exitCode = 66; // EX_NOINPUT
    return;
  }
  if (!observationsFile.existsSync()) {
    stderr.writeln('Observations file not found: ${observationsFile.path}');
    exitCode = 66;
    return;
  }

  final graph = graphFromJson(
    jsonDecode(graphFile.readAsStringSync()) as Map<String, Object?>,
  );
  final hazardInput = hazardInputFromJson(
    jsonDecode(observationsFile.readAsStringSync()) as Map<String, Object?>,
  );

  if (isBatch) {
    // One process, many queries (KNOWN_FLAWS F-20): the graph is parsed once
    // instead of once per pair, which is ~3 s of the old ~3 s per query. Each
    // line of stdout is one compact JSON object: a DecisionTrace, or
    // {"error": "no_route", ...} for an unreachable pair. Pairs are answered in
    // file order, so the output is deterministic.
    final pairsFile = File(args.option('pairs')!);
    if (!pairsFile.existsSync()) {
      stderr.writeln('Pairs file not found: ${pairsFile.path}');
      exitCode = 66;
      return;
    }
    final prefix = args.option('query-id-prefix')!;
    var index = 0;
    for (final line in pairsFile.readAsLinesSync()) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length != 2) continue;
      final source = int.parse(parts[0]);
      final target = int.parse(parts[1]);
      if (source < 0 ||
          source >= graph.nodeCount ||
          target < 0 ||
          target >= graph.nodeCount) {
        stdout.writeln(
          jsonEncode({
            'error': 'bad_node',
            'index': index,
            'source': source,
            'target': target,
          }),
        );
        index++;
        continue;
      }
      final trace = planRoute(
        graph: graph,
        source: source,
        target: target,
        computedAt: DateTime.parse(args.option('at')!),
        userClass: args.option('user-class')!,
        z: double.parse(args.option('z')!),
        lambda: double.parse(args.option('lambda')!),
        hazardConfigByEdge: hazardInput.hazardConfigByEdge,
        observationsByEdge: hazardInput.observationsByEdge,
        sourceClassByObservationId: hazardInput.sourceClassByObservationId,
        queryId: '$prefix-${index.toString().padLeft(4, '0')}',
        mode: args.option('mode')!,
      );
      stdout.writeln(
        trace == null
            ? jsonEncode({
                'error': 'no_route',
                'index': index,
                'source': source,
                'target': target,
              })
            : jsonEncode(trace.toJson()),
      );
      index++;
    }
    return;
  }

  final source = int.parse(args.option('source')!);
  final target = int.parse(args.option('target')!);
  if (source < 0 ||
      source >= graph.nodeCount ||
      target < 0 ||
      target >= graph.nodeCount) {
    stderr.writeln(
      'Node id out of range: the graph has ${graph.nodeCount} nodes '
      '(got source $source, target $target).',
    );
    exitCode = 65; // EX_DATAERR
    return;
  }

  final trace = planRoute(
    graph: graph,
    source: source,
    target: target,
    computedAt: DateTime.parse(args.option('at')!),
    userClass: args.option('user-class')!,
    z: double.parse(args.option('z')!),
    lambda: double.parse(args.option('lambda')!),
    hazardConfigByEdge: hazardInput.hazardConfigByEdge,
    observationsByEdge: hazardInput.observationsByEdge,
    sourceClassByObservationId: hazardInput.sourceClassByObservationId,
    queryId: args.option('query-id')!,
    mode: args.option('mode')!,
  );

  if (trace == null) {
    stderr.writeln('No route exists between the given source and target.');
    exitCode = 1;
    return;
  }

  stdout.writeln(trace.toJsonString());
}
