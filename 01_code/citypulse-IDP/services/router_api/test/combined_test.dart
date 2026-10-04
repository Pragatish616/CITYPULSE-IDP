// ADR-022: Chennai's detailed pack served inside the Tamil Nadu main-road region. A route inside
// Chennai gets the flood layer (and the app shows advice); anything that leaves Chennai gets the best
// main-road route with no flood layer.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:router_api/router_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _tnDir = '../../data/packs/tamil_nadu-backbone-2026-10-03';
const _chDir = '../../data/packs/2026-10-02';

ByteData _read(String dir, String name) =>
    ByteData.sublistView(File('$dir/$name').readAsBytesSync());

MapPack _pack(String dir) => MapPack.parse(
  graph: _read(dir, 'graph.bin'),
  nodes: _read(dir, 'nodes.bin'),
  meta: _read(dir, 'meta.bin'),
);

void main() {
  late Handler handler;
  late RoutingEngine tnEngine;
  late RoutingEngine chEngine;
  late CityConfig tn;
  late MapPack chPack;
  final fixedNow = DateTime.utc(2026, 10, 2, 6);

  setUpAll(() {
    final doc = (loadYaml(File('../../config/cities.yaml').readAsStringSync())
            as YamlMap)
        .cast<Object?, Object?>();
    tn = CityConfig.fromMap(doc, 'tamil_nadu');
    final ch = CityConfig.fromMap(doc, 'chennai');
    final config = EngineConfig.fromMap(
      loadYaml(File('../../config/hazard_classes.yaml').readAsStringSync())
          as YamlMap,
    );
    RoutingEngine engine(MapPack p) => RoutingEngine(
      pack: p,
      hazardClasses: config.hazardClasses,
      userClasses: config.userClasses,
      travelProfiles: config.travelProfiles,
      sourceReliability: config.sourceReliability,
      eventState: EventState.active,
    );
    final tnPack = _pack(_tnDir);
    chPack = _pack(_chDir);
    tnEngine = engine(tnPack);
    chEngine = engine(chPack);
    handler = buildHandler(
      tnEngine,
      places: PlaceIndex(
        tnPack,
        gazetteer: parseGazetteer(File('$_tnDir/places.json').readAsStringSync()),
      ),
      details: [
        DetailRegion(city: ch, engine: chEngine, places: PlaceIndex(chPack)),
      ],
      config: ApiConfig(
        cityId: tn.id,
        cityName: 'Tamil Nadu',
        maxSnapMetres: tn.maxSnapMetres,
        hazardLayer: tn.hazardLayer,
        adminToken: 'tok',
      ),
      now: () => fixedNow,
    );
  });

  Future<Response> call(String method, String path, {Object? body, Map<String, String>? headers}) =>
      Future.sync(
        () => handler(
          Request(
            method,
            Uri.parse('http://localhost$path'),
            body: body == null ? null : jsonEncode(body),
            headers: headers,
          ),
        ),
      );

  Future<Map<String, Object?>> routeJson(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
  ) async {
    final r = await call(
      'POST',
      '/route',
      body: {
        'from': {'lat': fromLat, 'lon': fromLon},
        'to': {'lat': toLat, 'lon': toLon},
      },
    );
    expect(r.statusCode, 200);
    return jsonDecode(await r.readAsString()) as Map<String, Object?>;
  }

  test('the config makes Chennai a detail region of Tamil Nadu', () {
    expect(tn.detailRegions, ['chennai']);
    expect(tn.hazardLayer, isFalse);
  });

  test('a route with both ends inside Chennai uses the Chennai pack and its flood layer', () async {
    final j = await routeJson(
      chPack.nodeLat[31140],
      chPack.nodeLon[31140],
      chPack.nodeLat[47036],
      chPack.nodeLon[47036],
    );
    expect(j['region'], 'chennai');
    expect(j['hazard_layer'], isTrue);
  });

  test('a route that leaves Chennai uses the main-road pack, with no flood layer', () async {
    // T. Nagar to Madurai.
    final j = await routeJson(13.0418, 80.2341, 9.9252, 78.1198);
    expect(j['region'], 'tamil_nadu');
    expect(j['hazard_layer'], isFalse);
    final km = (((j['trace']! as Map)['chosen']! as Map)['distance_m']! as num) / 1000;
    expect(km, inInclusiveRange(380, 520), reason: 'Chennai to Madurai is about 460 km by road');
  });

  test('a route entirely outside Chennai also has no flood layer', () async {
    final j = await routeJson(9.9252, 78.1198, 11.0168, 76.9558); // Madurai to Coimbatore
    expect(j['region'], 'tamil_nadu');
    expect(j['hazard_layer'], isFalse);
  });

  test('the flood overlay comes from Chennai only', () async {
    final inChennai = jsonDecode(
      await (await call('GET', '/risk?bbox=80.15,12.95,80.3,13.15&limit=500')).readAsString(),
    ) as Map<String, Object?>;
    expect((inChennai['features']! as List), isNotEmpty);
    final elsewhere = jsonDecode(
      await (await call('GET', '/risk?bbox=77.9,9.8,78.3,10.1&limit=500')).readAsString(),
    ) as Map<String, Object?>;
    expect((elsewhere['features']! as List), isEmpty);
  });

  test('search finds both a state town and a Chennai street, towns first', () async {
    Future<List<Map<String, Object?>>> search(String q) async {
      final r = await call('GET', '/places?q=${Uri.encodeQueryComponent(q)}&limit=8');
      final j = jsonDecode(await r.readAsString()) as Map<String, Object?>;
      return [for (final m in j['results']! as List) m as Map<String, Object?>];
    }

    final madurai = await search('madurai');
    expect(madurai.first['name'], 'Madurai');
    final streets = await search('anna salai');
    expect(streets, isNotEmpty);
    expect(
      streets.any((m) {
        final lat = m['lat']! as num;
        final lon = m['lon']! as num;
        return lat > 12.75 && lat < 13.25 && lon > 79.95 && lon < 80.35;
      }),
      isTrue,
      reason: 'a Chennai street comes from the Chennai index',
    );
  });

  test('health names the detail regions, and the event state reaches both engines', () async {
    final h = jsonDecode(await (await call('GET', '/health')).readAsString()) as Map<String, Object?>;
    expect(h['detail_regions'], ['chennai']);
    final r = await call(
      'PUT',
      '/event-state',
      body: {'event_state': 'dry'},
      headers: {'x-admin-token': 'tok'},
    );
    expect(r.statusCode, 200);
    expect(tnEngine.eventState, EventState.dry);
    expect(chEngine.eventState, EventState.dry);
    await call('PUT', '/event-state', body: {'event_state': 'active'}, headers: {'x-admin-token': 'tok'});
  });
}
