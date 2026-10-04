import 'dart:convert';

import 'package:citypulse_app/src/platform/observation_puller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _row(String id, String received) => {
  'id': id,
  'hazard_class': 'flood',
  'polarity': 1,
  'geometry': {
    'type': 'Point',
    'coordinates': [80.2, 13.05],
  },
  'accuracy_m': 20.0,
  'observed_at': '2026-10-02T09:00:00Z',
  'received_at': received,
  'source_class': 'crowd',
  'source_id': 'install:x',
};

void main() {
  test('the first pull takes everything, later pulls ask only for reports '
      'received since the newest one seen', () async {
    final urls = <Uri>[];
    final client = MockClient((req) async {
      urls.add(req.url);
      return http.Response(
        jsonEncode([
          _row('00000000-0000-7000-8000-000000000001', '2026-10-02T11:00:00Z'),
          _row('00000000-0000-7000-8000-000000000002', '2026-10-02T10:00:00Z'),
          {'id': 'junk'},
        ]),
        200,
      );
    });
    final puller = ObservationPuller(
      ingestUrl: 'http://ingest.test',
      client: client,
    );
    expect(puller.cursor, isNull);
    final first = await puller.pull();
    expect(first, hasLength(2), reason: 'the malformed row is skipped');
    expect(urls[0].queryParameters, isEmpty);
    expect(puller.cursor, DateTime.utc(2026, 10, 2, 11));

    await puller.pull();
    expect(urls[1].queryParameters['received_since'], '2026-10-02T11:00:00.000Z');
  });

  test('a failed pull leaves the cursor alone so the next one retries the '
      'same window', () async {
    var fail = false;
    final puller = ObservationPuller(
      ingestUrl: 'http://ingest.test',
      client: MockClient((_) async {
        if (fail) throw http.ClientException('offline');
        return http.Response(
          jsonEncode([
            _row('00000000-0000-7000-8000-000000000003', '2026-10-02T12:00:00Z'),
          ]),
          200,
        );
      }),
    );
    await puller.pull();
    fail = true;
    await expectLater(puller.pull(), throwsA(isA<http.ClientException>()));
    expect(puller.cursor, DateTime.utc(2026, 10, 2, 12));
  });

  test('a server error yields no reports and does not move the cursor',
      () async {
    final puller = ObservationPuller(
      ingestUrl: 'http://ingest.test',
      client: MockClient((_) async => http.Response('boom', 500)),
    );
    expect(await puller.pull(), isEmpty);
    expect(puller.cursor, isNull);
  });
}
