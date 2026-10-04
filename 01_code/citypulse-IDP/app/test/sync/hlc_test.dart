// T5.4 -- Hybrid Logical Clock unit tests (`docs/IMPLEMENTATION_PLAN.md`,
// ADR-008). Pure, no storage/network -- exercises `now()`/`update()` against
// an injected fake physical clock so behaviour is deterministic.
import 'package:citypulse_app/src/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HlcTimestamp', () {
    test('encode/parse round-trips exactly', () {
      const stamp = HlcTimestamp(
        logical: 1757659200123,
        counter: 42,
        nodeId: 'device-abc',
      );
      final parsed = HlcTimestamp.parse(stamp.encode());
      expect(parsed, equals(stamp));
    });

    test('compareTo orders by logical, then counter, then nodeId', () {
      const a = HlcTimestamp(logical: 100, counter: 0, nodeId: 'a');
      const b = HlcTimestamp(logical: 200, counter: 0, nodeId: 'a');
      const c = HlcTimestamp(logical: 100, counter: 1, nodeId: 'a');
      const d = HlcTimestamp(logical: 100, counter: 0, nodeId: 'b');

      expect(a < b, isTrue);
      expect(a < c, isTrue);
      expect(a < d, isTrue);
      expect(b > c, isTrue);
    });

    test('parse rejects a malformed encoding', () {
      expect(
        () => HlcTimestamp.parse('not-a-valid-hlc'),
        throwsFormatException,
      );
      expect(
        () => HlcTimestamp.parse('2026-09-12T00:00:00Z/not-a-number/node'),
        throwsFormatException,
      );
    });
  });

  group('HybridLogicalClock.now (local events)', () {
    test('advances logical time and resets counter when physical time '
        'genuinely advances', () {
      var physical = 1000;
      final clock = HybridLogicalClock(
        nodeId: 'node-1',
        physicalTimeMs: () => physical,
      );

      final first = clock.now();
      expect(first.logical, 1000);
      expect(first.counter, 0);

      physical = 2000;
      final second = clock.now();
      expect(second.logical, 2000);
      expect(second.counter, 0);
      expect(second > first, isTrue);
    });

    test('monotonicity: successive now() calls strictly increase even when '
        'the physical clock does not advance (stalled clock)', () {
      const stalledTime = 5000;
      final clock = HybridLogicalClock(
        nodeId: 'node-1',
        physicalTimeMs: () => stalledTime,
      );

      final stamps = List.generate(5, (_) => clock.now());
      for (var i = 1; i < stamps.length; i++) {
        expect(
          stamps[i] > stamps[i - 1],
          isTrue,
          reason:
              'stamp $i (${stamps[i]}) must exceed stamp ${i - 1} '
              '(${stamps[i - 1]}) despite a stalled physical clock',
        );
        expect(
          stamps[i].logical,
          stalledTime,
          reason:
              'logical time must not '
              'advance past the (stalled) physical clock',
        );
        expect(stamps[i].counter, stamps[i - 1].counter + 1);
      }
    });

    test('monotonicity: a physical clock that jumps backwards does not '
        'move the HLC backwards', () {
      var physical = 9000;
      final clock = HybridLogicalClock(
        nodeId: 'node-1',
        physicalTimeMs: () => physical,
      );

      final before = clock.now();
      physical = 1000; // clock jumped back, e.g. NTP correction
      final after = clock.now();

      expect(after > before, isTrue);
      expect(
        after.logical,
        before.logical,
        reason:
            'logical time holds at '
            'its previous high-water mark rather than regressing',
      );
      expect(after.counter, before.counter + 1);
    });
  });

  group('HybridLogicalClock.update (receive events / merge)', () {
    test('remote ahead of both local logical and physical time: adopts '
        "remote's logical time, counter = remote.counter + 1", () {
      final clock = HybridLogicalClock(
        nodeId: 'local',
        physicalTimeMs: () => 1000,
      )..now(); // local state: logical=1000, counter=0

      const remote = HlcTimestamp(logical: 5000, counter: 3, nodeId: 'peer');
      final merged = clock.update(remote);

      expect(merged.logical, 5000);
      expect(merged.counter, 4);
    });

    test('local ahead of remote and physical time: keeps local logical '
        'time, increments local counter', () {
      var physical = 100;
      final clock = HybridLogicalClock(
        nodeId: 'local',
        physicalTimeMs: () => physical,
      );
      physical = 9000;
      final local = clock.now(); // logical=9000, counter=0

      const remote = HlcTimestamp(logical: 500, counter: 9, nodeId: 'peer');
      physical = 200; // physical clock behind both
      final merged = clock.update(remote);

      expect(merged.logical, local.logical);
      expect(merged.counter, local.counter + 1);
    });

    test('local and remote logical times tie: counter merges as '
        'max(local, remote) + 1, not just one side', () {
      final clock =
          HybridLogicalClock(nodeId: 'local', physicalTimeMs: () => 1000)
            ..now()
            ..now()
            ..now(); // local: logical=1000, counter=2

      const remote = HlcTimestamp(logical: 1000, counter: 5, nodeId: 'peer');
      final merged = clock.update(remote);

      expect(merged.logical, 1000);
      expect(merged.counter, 6); // max(2, 5) + 1
    });

    test('remote logical time exceeds a stale local physical clock: remote '
        'wins, counter = remote.counter + 1', () {
      final clock = HybridLogicalClock(
        nodeId: 'local',
        physicalTimeMs: () => 1000,
      )..now(); // local: logical=1000, counter=0

      const remote = HlcTimestamp(logical: 1200, counter: 7, nodeId: 'peer');
      final merged = clock.update(remote); // physical still reads 1000

      expect(merged.logical, 1200);
      expect(merged.counter, 8);
    });

    test('physical time genuinely exceeds both local and remote logical '
        'time: fresh instant, counter resets to 0', () {
      var physical = 1000;
      final clock = HybridLogicalClock(
        nodeId: 'local',
        physicalTimeMs: () => physical,
      )..now(); // local: logical=1000, counter=0

      const remote = HlcTimestamp(logical: 1200, counter: 7, nodeId: 'peer');
      physical = 9999; // the local wall clock has since ticked past both
      final merged = clock.update(remote);

      expect(merged.logical, 9999);
      expect(merged.counter, 0);
    });

    test('update() result is itself monotonic with respect to prior now() '
        'calls', () {
      final clock = HybridLogicalClock(
        nodeId: 'local',
        physicalTimeMs: () => 1000,
      );
      final before = clock.now();
      const remote = HlcTimestamp(logical: 1000, counter: 0, nodeId: 'peer');
      final after = clock.update(remote);
      expect(after > before, isTrue);
    });

    test('clock-skew tolerance: a remote timestamp within maxDriftMs is '
        'accepted', () {
      final clock = HybridLogicalClock(
        nodeId: 'local',
        physicalTimeMs: () => 1000,
        maxDriftMs: const Duration(minutes: 5).inMilliseconds,
      );
      final remote = HlcTimestamp(
        logical: 1000 + const Duration(minutes: 4).inMilliseconds,
        counter: 0,
        nodeId: 'peer',
      );
      expect(() => clock.update(remote), returnsNormally);
    });

    test('clock-skew tolerance: a remote timestamp beyond maxDriftMs is '
        'rejected with ClockSkewException, and does not mutate state', () {
      final clock = HybridLogicalClock(
        nodeId: 'local',
        physicalTimeMs: () => 1000,
        maxDriftMs: const Duration(minutes: 5).inMilliseconds,
      );
      final before = clock.now();
      final farFuture = HlcTimestamp(
        logical: 1000 + const Duration(hours: 1).inMilliseconds,
        counter: 0,
        nodeId: 'peer',
      );

      expect(() => clock.update(farFuture), throwsA(isA<ClockSkewException>()));
      // State must be unchanged by the rejected merge.
      expect(clock.last, equals(before));
    });
  });
}
