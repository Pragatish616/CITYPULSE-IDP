// T5.2 -- local hazard cache tests (`docs/IMPLEMENTATION_PLAN.md`).
//
// Uses Drift's documented in-memory `NativeDatabase.memory()` test pattern
// (drift.simonbinder.eu, "Testing") -- a fresh, isolated database per test
// via `setUp`, never touching disk.
import 'package:citypulse_app/src/storage/hazard_cache.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

HazardObservationRecord _obs({
  required String id,
  required double lat,
  required double lon,
  DateTime? observedAt,
  String sourceClass = 'crowd',
  String sourceId = 'device-123',
  Map<String, dynamic>? intensity,
  Map<String, dynamic>? raw,
}) {
  final at = observedAt ?? DateTime.utc(2026, 9, 12, 5, 14, 22);
  return HazardObservationRecord(
    id: id,
    hazardClass: 'flood',
    polarity: 1,
    lat: lat,
    lon: lon,
    accuracyM: 12,
    observedAt: at,
    receivedAt: at.add(const Duration(seconds: 7)),
    sourceClass: sourceClass,
    sourceId: sourceId,
    intensity: intensity ?? {'depth_mm': 320},
    raw: raw ?? {'note': 'kotturpuram bridge approach'},
  );
}

void main() {
  late HazardDatabase db;
  late HazardCache cache;

  setUp(() {
    db = HazardDatabase(NativeDatabase.memory());
    cache = HazardCache(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('insertObservation', () {
    test('round-trips every field exactly', () async {
      final obs = _obs(id: 'obs-1', lat: 13.0827, lon: 80.2707);

      final wasNew = await cache.insertObservation(obs);
      expect(wasNew, isTrue);

      final found = await cache.observationsInBbox(
        minLat: 13,
        minLon: 80.2,
        maxLat: 13.2,
        maxLon: 80.3,
      );

      expect(found, hasLength(1));
      expect(found.single, equals(obs));
    });

    test('duplicate id is a no-op (G-Set CRDT property, ADR-008)', () async {
      final first = _obs(
        id: 'dup-1',
        lat: 13.0827,
        lon: 80.2707,
        sourceId: 'first-report',
      );
      final replay = _obs(
        id: 'dup-1',
        lat: 20,
        lon: 20,
        sourceId: 'a-different-later-report',
      );

      final firstInsert = await cache.insertObservation(first);
      final secondInsert = await cache.insertObservation(replay);

      expect(firstInsert, isTrue);
      expect(secondInsert, isFalse, reason: 'replayed insert must no-op');

      final found = await cache.observationsInBbox(
        minLat: -90,
        minLon: -180,
        maxLat: 90,
        maxLon: 180,
      );

      expect(found, hasLength(1));
      expect(
        found.single,
        equals(first),
        reason: 'the original row must be unchanged by the replay',
      );
    });
  });

  group('observationsInBbox', () {
    test('excludes a point just outside the box', () async {
      final inside = _obs(id: 'inside', lat: 13.05, lon: 80.25);
      final justOutside = _obs(id: 'outside', lat: 13.05, lon: 80.31);

      await cache.insertObservation(inside);
      await cache.insertObservation(justOutside);

      final found = await cache.observationsInBbox(
        minLat: 13,
        minLon: 80.2,
        maxLat: 13.1,
        maxLon: 80.3,
      );

      expect(found.map((o) => o.id), [inside.id]);
    });

    test('a since filter excludes older observations', () async {
      final old = _obs(
        id: 'old',
        lat: 13.05,
        lon: 80.25,
        observedAt: DateTime.utc(2026),
      );
      final recent = _obs(
        id: 'recent',
        lat: 13.05,
        lon: 80.25,
        observedAt: DateTime.utc(2026, 9, 12),
      );

      await cache.insertObservation(old);
      await cache.insertObservation(recent);

      final found = await cache.observationsInBbox(
        minLat: 13,
        minLon: 80.2,
        maxLat: 13.1,
        maxLon: 80.3,
        since: DateTime.utc(2026, 6),
      );

      expect(found.map((o) => o.id), [recent.id]);
    });

    test(
      'the bbox predicate actually uses the R*Tree virtual table index',
      () async {
        // Belt-and-suspenders check alongside the correctness tests above:
        // the task card asks to "verify with EXPLAIN QUERY PLAN ... or at
        // minimum prove correctness with a test that would fail if it
        // silently fell back to a full scan returning wrong results." The
        // tests above are that correctness proof; this one is the direct
        // EXPLAIN QUERY PLAN check.
        await cache.insertObservation(_obs(id: 'a', lat: 13.05, lon: 80.25));

        final plan = await db
            .customSelect(
              'EXPLAIN QUERY PLAN '
              'SELECT o.id AS obs_id '
              'FROM observations_rtree AS r '
              'JOIN observations AS o ON o.rowid = r.id '
              'WHERE r.minLat <= ? AND r.maxLat >= ? '
              'AND r.minLon <= ? AND r.maxLon >= ?',
              variables: [
                Variable.withReal(90),
                Variable.withReal(-90),
                Variable.withReal(180),
                Variable.withReal(-180),
              ],
            )
            .get();

        final detail = plan.map((row) => row.read<String>('detail')).join('\n');
        expect(
          detail.toUpperCase(),
          contains('VIRTUAL TABLE'),
          reason:
              'query plan should scan observations_rtree as a virtual '
              'table, not fall back to a full scan of observations:\n'
              '$detail',
        );
      },
    );
  });

  group('coarsenObservation', () {
    test(
      'changes only the ADR-010-permitted fields, for a crowd source',
      () async {
        final obs = _obs(
          id: 'coarsen-1',
          lat: 13.0827,
          lon: 80.2707,
          sourceId: 'raw-device-id-abc',
        );
        await cache.insertObservation(obs);

        final at = DateTime.utc(2026, 10, 12);
        await cache.coarsenObservation(obs.id, coarsenedAt: at);

        final found = (await cache.observationsInBbox(
          minLat: -90,
          minLon: -180,
          maxLat: 90,
          maxLon: 180,
        )).single;

        // Immutable facts (ADR-008/ADR-010): untouched.
        expect(found.id, obs.id);
        expect(found.polarity, obs.polarity);
        expect(found.hazardClass, obs.hazardClass);
        expect(found.observedAt, obs.observedAt);

        // Permitted mutations.
        expect(found.precisionState, PrecisionState.coarsened);
        expect(found.coarsenedAt, at);
        expect(found.lat, isNot(obs.lat));
        expect(found.lon, isNot(obs.lon));
        expect(
          found.sourceId,
          isNot(obs.sourceId),
          reason: 'crowd source_id must be rehashed to a bucket id',
        );
        expect(found.sourceId, startsWith('bucket_'));
      },
    );

    test(
      'does not rehash source_id for a non-crowd, non-app_traversal source',
      () async {
        final obs = _obs(
          id: 'coarsen-2',
          lat: 13.0827,
          lon: 80.2707,
          sourceClass: 'municipal_sensor',
          sourceId: 'cmwssb.reservoir.chembarambakkam',
        );
        await cache.insertObservation(obs);

        await cache.coarsenObservation(obs.id);

        final found = (await cache.observationsInBbox(
          minLat: -90,
          minLon: -180,
          maxLat: 90,
          maxLon: 180,
        )).single;

        expect(found.sourceId, obs.sourceId);
        expect(found.precisionState, PrecisionState.coarsened);
      },
    );

    test('keeps the rtree shadow row in sync after coarsening', () async {
      final obs = _obs(id: 'coarsen-3', lat: 13.0827, lon: 80.2707);
      await cache.insertObservation(obs);
      await cache.coarsenObservation(obs.id);

      // The point moved -- a bbox around the *original* location must no
      // longer find it, proving the rtree shadow row (not just the base
      // table row) was updated.
      final atOldLocation = await cache.observationsInBbox(
        minLat: 13.0826,
        minLon: 80.2706,
        maxLat: 13.0828,
        maxLon: 80.2708,
      );
      expect(atOldLocation, isEmpty);

      final anywhere = await cache.observationsInBbox(
        minLat: -90,
        minLon: -180,
        maxLat: 90,
        maxLon: 180,
      );
      expect(anywhere, hasLength(1));
    });
  });

  group('observationById', () {
    test('returns the stored record for a known id', () async {
      final obs = _obs(id: 'by-id-1', lat: 13.0827, lon: 80.2707);
      await cache.insertObservation(obs);

      final found = await cache.observationById('by-id-1');
      expect(found, equals(obs));
    });

    test('returns null for an unknown id', () async {
      final found = await cache.observationById('does-not-exist');
      expect(found, isNull);
    });
  });

  group('outbox', () {
    test(
      'enqueue -> pendingOutbox returns it -> markOutboxSynced removes it',
      () async {
        final obs = _obs(id: 'outbox-1', lat: 13.0827, lon: 80.2707);
        await cache.insertObservation(obs);

        await cache.enqueueOutbox(obs.id);
        final pending = await cache.pendingOutbox();
        expect(pending.map((e) => e.observationId), [obs.id]);
        expect(pending.single.syncedAt, isNull);

        await cache.markOutboxSynced(obs.id);
        final afterSync = await cache.pendingOutbox();
        expect(afterSync, isEmpty);
      },
    );
  });
}
