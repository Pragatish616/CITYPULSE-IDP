// F-16: the cloud tier talks only to the project's own proxy and carries no key.
import 'dart:convert';

import 'package:citypulse_app/src/explain/cloud_rewriter.dart';
import 'package:citypulse_app/src/explain/fact_set.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers/harness.dart';

void main() {
  final facts = FactSet.fromTrace(sampleTrace());

  test('posts only the facts to <router_api>/rewrite, with no credentials, '
      'and returns the proxy text', () async {
    late http.Request seen;
    final r = CloudRewriter(
      routerApiUrl: 'http://api.test/',
      httpClient: MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'text': 'Route A is 2 min slower.'}), 200);
      }),
    );
    expect(r.isAvailable, isTrue);
    expect(r.tier, 2);
    expect(await r.generate(facts), 'Route A is 2 min slower.');
    expect(seen.url.toString(), 'http://api.test/rewrite');
    expect(seen.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    expect(jsonDecode(seen.body), {'facts': facts.toJson()});
  });

  test('without an address it is unavailable and throws, so the pipeline '
      'falls back to the template', () async {
    final r = CloudRewriter(routerApiUrl: null);
    expect(r.isAvailable, isFalse);
    await expectLater(r.generate(facts), throwsStateError);
  });

  test('a 503 (proxy has no key) or an empty reply throws', () async {
    for (final response in [
      http.Response('{"error":"rewrite_unavailable"}', 503),
      http.Response('{"text":""}', 200),
      http.Response('[]', 200),
    ]) {
      final r = CloudRewriter(
        routerApiUrl: 'http://api.test',
        httpClient: MockClient((_) async => response),
      );
      await expectLater(r.generate(facts), throwsStateError);
    }
  });
}
