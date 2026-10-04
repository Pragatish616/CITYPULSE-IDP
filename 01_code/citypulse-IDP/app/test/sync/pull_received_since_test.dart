// KNOWN_FLAWS F-10: the pull cursor on server arrival time.
import 'dart:convert';

import 'package:citypulse_app/src/storage/hazard_cache.dart';
import 'package:citypulse_app/src/storage/hazard_database.dart';
import 'package:citypulse_app/src/sync/hlc.dart';
import 'package:citypulse_app/src/sync/sync_client.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('pullReceivedSince asks the server for received_since and stores the '
      'late-uploaded report', () async {
    final db = HazardDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = HazardCache(db);
    Uri? seen;
    final client = MockClient((req) async {
      seen = req.url;
      return http.Response(
        jsonEncode([
          {
            'id': 'e8400000-0000-4000-8000-000000000009',
            'hazard_class': 'flood',
            'polarity': 1,
            'geometry': {
              'type': 'Point',
              'coordinates': [80.2, 13.05],
            },
            'accuracy_m': 20.0,
            // Made at 09:00, uploaded at 11:00.
            'observed_at': '2026-10-02T09:00:00Z',
            'received_at': '2026-10-02T11:00:00Z',
            'source_class': 'crowd',
            'source_id': 'offline-device',
            'precision_state': 'exact',
          },
        ]),
        200,
      );
    });
    final sync = SyncClient(
      cache: cache,
      baseUri: Uri.parse('http://ingest.test/'),
      clock: HybridLogicalClock(nodeId: 'test'),
      httpClient: client,
    );
    final inserted = await sync.pullReceivedSince(DateTime.utc(2026, 10, 2, 10));
    expect(inserted, 1);
    expect(seen!.path, '/observations');
    expect(seen!.queryParameters['received_since'], '2026-10-02T10:00:00.000Z');
    expect(seen!.queryParameters.containsKey('since'), isFalse);
    sync.close();
  });
}
