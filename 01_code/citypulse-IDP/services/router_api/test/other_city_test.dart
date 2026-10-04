// ADR-018: the same HTTP service, pointed at a pack built for a different city
// ("Testville", a SYNTHETIC grid, see scripts/tests/make_testville_fixture.py).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:router_api/router_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _dir = '../../packages/pulse_router/test/fixtures/testville';

ByteData _read(String name) =>
    ByteData.sublistView(File('$_dir/$name').readAsBytesSync());

void main() {
  late Handler handler;

  setUpAll(() {
    final pack = MapPack.parse(
      graph: _read('graph.bin'),
      nodes: _read('nodes.bin'),
      meta: _read('meta.bin'),
    );
    final hazards = EngineConfig.fromMap(
      loadYaml(File('../../config/hazard_classes.yaml').readAsStringSync())
          as YamlMap,
    );
    final engine = RoutingEngine(
      pack: pack,
      hazardClasses: hazards.hazardClasses,
      userClasses: hazards.userClasses,
      travelProfiles: hazards.travelProfiles,
      sourceReliability: hazards.sourceReliability,
    );
    handler = buildHandler(
      engine,
      places: PlaceIndex(pack),
      config: const ApiConfig(cityId: 'testville', cityName: 'Testville'),
      now: () => DateTime.utc(2026, 10, 3, 6),
    );
  });

  Future<Map<String, Object?>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  Future<Response> post(String path, Object body) => Future.sync(
    () => handler(
      Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: jsonEncode(body),
      ),
    ),
  );

  Future<Response> get(String path) =>
      Future.sync(() => handler(Request('GET', Uri.parse('http://localhost$path'))));

  test('/health names the city and the pack size', () async {
    final j = await json(await get('/health'));
    expect(j['city'], 'testville');
    expect(j['nodes'], 36);
    expect(j['edges'], 113);
  });

  test('a route inside the city is found', () async {
    final r = await post('/route', {
      'from': {'lat': 20.0, 'lon': 78.0},
      'to': {'lat': 20.016, 'lon': 78.016},
      'user_class': 'commuter',
    });
    expect(r.statusCode, 200);
    final j = await json(r);
    expect((j['path']! as List).length, greaterThan(3));
  });

  test('a point in Chennai is refused with a message that names Testville, '
      'not Chennai', () async {
    final r = await post('/route', {
      'from': {'lat': 13.0419, 'lon': 80.2339},
      'to': {'lat': 20.01, 'lon': 78.01},
      'user_class': 'commuter',
    });
    expect(r.statusCode, 422);
    final j = await json(r);
    expect(j['reason'], 'origin_outside_coverage');
    expect(j['message'], contains('Testville'));
    expect(j['message'], isNot(contains('Chennai')));
  });

  test('street search and the risk overlay work with no hazard layer', () async {
    final places = jsonDecode(
      await (await get('/places?q=ring')).readAsString(),
    );
    final text = jsonEncode(places);
    expect(text, contains('Ring Road'));
    final risk = await json(await get('/risk?user_class=commuter'));
    expect((risk['features']! as List), isEmpty);
  });
}
