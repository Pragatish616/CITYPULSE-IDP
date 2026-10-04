import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Runs the CLI via `dart run` (not the AOT-compiled binary -- that would
/// need a build step this test suite doesn't own) with [args] appended
/// after `bin/pulse_router.dart`.
ProcessResult runCli(List<String> args) =>
    Process.runSync('dart', ['run', 'bin/pulse_router.dart', ...args]);

void main() {
  group('pulse_router CLI (T2.4)', () {
    test('route: emits a DecisionTrace whose chance-constraint-removed edge '
        'and detour match the hand-derived expectation from '
        "query_orchestrator_test.dart's equivalent in-process case", () {
      final result = runCli([
        'route',
        '--graph',
        'test/fixtures/smoke_graph.json',
        '--observations',
        'test/fixtures/smoke_observations.json',
        '--source',
        '0',
        '--target',
        '1',
        '--at',
        '2026-09-14T12:00:00Z',
        '--user-class',
        'emergency',
        '--z',
        '2.0',
        '--lambda',
        '1.0',
        '--query-id',
        'cli-smoke-test',
      ]);

      expect(result.exitCode, equals(0), reason: result.stderr.toString());
      final trace = jsonDecode(result.stdout as String) as Map<String, Object?>;

      expect(trace['query_id'], equals('cli-smoke-test'));
      final chosen = trace['chosen']! as Map<String, Object?>;
      expect(chosen['duration_s'], equals(40)); // forced detour via 0 -> 2 -> 1

      final alternatives = trace['alternatives']! as List<Object?>;
      expect(alternatives, hasLength(1));
      final alt = alternatives.single! as Map<String, Object?>;
      expect(alt['rejected_because'], equals('chance_constraint'));
      final blocking =
          (alt['blocking_edges']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(blocking['edge_id'], equals(0));
      expect(blocking['removed_by_chance_constraint'], isTrue);
      expect(blocking['source_class'], equals('crowd'));

      expect(trace['confidence_band'], equals('low'));
      // F-08 (ADR-016): the two detour edges carry no hazard prior at all, so
      // they are not listed as data gaps; "low" confidence already says the
      // route rests on thin data. (Before the fix this asserted length 2: the
      // unhazarded edges were flagged and high-prior unreported ones were not.)
      expect(trace['data_gaps'], isEmpty);
    });

    test('route-batch answers many pairs from one process, in file order, '
        'and reports an unreachable pair as an error line', () {
      final dir = Directory.systemTemp.createTempSync('pulse_batch');
      addTearDown(() => dir.deleteSync(recursive: true));
      final pairs = File('${dir.path}/pairs.txt')
        ..writeAsStringSync('0 1\n1 0\n0 99\n');
      final result = runCli([
        'route-batch',
        '--graph',
        'test/fixtures/smoke_graph.json',
        '--observations',
        'test/fixtures/smoke_observations.json',
        '--pairs',
        pairs.path,
        '--at',
        '2026-09-14T12:00:00Z',
        '--user-class',
        'emergency',
        '--z',
        '2.0',
        '--lambda',
        '1.0',
        '--query-id-prefix',
        'b',
      ]);
      expect(result.exitCode, equals(0), reason: result.stderr.toString());
      final lines = (result.stdout as String)
          .trim()
          .split('\n')
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .toList();
      expect(lines, hasLength(3));
      expect(lines[0]['query_id'], 'b-0000');
      expect((lines[0]['chosen']! as Map)['duration_s'], equals(40));
      expect(lines[1]['error'], 'no_route'); // 1 -> 0: no road back
      expect(lines[1]['index'], 1);
      expect(lines[2]['error'], 'bad_node'); // node 99 is not in a 3-node graph
      expect(lines[2]['index'], 2);

      // Identical to the one-shot command for the first pair.
      final single = runCli([
        'route',
        '--graph',
        'test/fixtures/smoke_graph.json',
        '--observations',
        'test/fixtures/smoke_observations.json',
        '--source',
        '0',
        '--target',
        '1',
        '--at',
        '2026-09-14T12:00:00Z',
        '--user-class',
        'emergency',
        '--z',
        '2.0',
        '--lambda',
        '1.0',
        '--query-id',
        'b-0000',
      ]);
      expect(
        jsonEncode(lines[0]),
        equals(jsonEncode(jsonDecode(single.stdout as String))),
      );
    });

    test('bad usage (missing "route" subcommand) exits with code 64 and a '
        'usage message', () {
      final result = runCli([]);
      expect(result.exitCode, equals(64));
      expect(result.stderr, contains('Usage: pulse_router route'));
    });

    test('missing graph file exits with code 66 and a clear message', () {
      final result = runCli([
        'route',
        '--graph',
        'test/fixtures/does_not_exist.json',
        '--observations',
        'test/fixtures/smoke_observations.json',
        '--source',
        '0',
        '--target',
        '1',
        '--at',
        '2026-09-14T12:00:00Z',
        '--user-class',
        'commuter',
        '--z',
        '0',
        '--lambda',
        '0.3',
      ]);
      expect(result.exitCode, equals(66));
      expect(result.stderr, contains('Graph file not found'));
    });

    test('an unreachable target exits with code 1 and a clear message, not '
        'a stack trace', () {
      final result = runCli([
        'route',
        '--graph',
        'test/fixtures/smoke_graph.json',
        '--observations',
        'test/fixtures/smoke_observations.json',
        '--source',
        '1',
        '--target',
        '0',
        '--at',
        '2026-09-14T12:00:00Z',
        '--user-class',
        'commuter',
        '--z',
        '0',
        '--lambda',
        '0.3',
      ]);
      expect(result.exitCode, equals(1));
      expect(result.stderr, contains('No route exists'));
    });
  });
}
