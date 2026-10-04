// ADR-020: a state-sized map is searched by place names (cities, towns, villages) as well as streets.
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

ByteData _read(String name) =>
    ByteData.sublistView(File('test/fixtures/testville/$name').readAsBytesSync());

void main() {
  late MapPack pack;

  setUpAll(() {
    pack = MapPack.parse(
      graph: _read('graph.bin'),
      nodes: _read('nodes.bin'),
      meta: _read('meta.bin'),
    );
  });

  const places = [
    GazetteerEntry(name: 'Ring Village', lat: 20.01, lon: 78.01, kind: 'village'),
    GazetteerEntry(name: 'Ringtown', lat: 20.012, lon: 78.012, kind: 'town'),
    GazetteerEntry(
      name: 'Madurai',
      lat: 9.9252,
      lon: 78.1198,
      kind: 'city',
      altNames: ['மதுரை', 'Madura'],
    ),
    GazetteerEntry(name: 'Madurai Colony', lat: 10.2, lon: 78.3, kind: 'village'),
  ];

  group('parseGazetteer', () {
    test('reads rows, with alternative names, and skips the malformed ones', () {
      final out = parseGazetteer(
        '{"version":1,"places":['
        '["Madurai",9.9252,78.1198,"city","மதுரை"],'
        '["Salem",11.66,78.14,"city"],'
        '["no coordinates"],'
        '[null,1,2,"town"],'
        '["Bad kind",1,2,7],'
        '"not a row"'
        ']}',
      );
      expect(out.map((g) => g.name), ['Madurai', 'Salem']);
      expect(out.first.altNames, ['மதுரை']);
    });

    test('anything that is not the expected document gives an empty list', () {
      expect(parseGazetteer('{"places": 3}'), isEmpty);
      expect(parseGazetteer('[]'), isEmpty);
    });
  });

  group('searching places along with streets', () {
    final index = () => PlaceIndex(pack, gazetteer: places);

    test('a city is listed before a village that matches equally well', () {
      final r = index().search('madurai');
      expect(r.first.name, 'Madurai');
      expect(r.first.kind, 'city');
      expect(r.map((m) => m.name), contains('Madurai Colony'));
      expect(r.map((m) => m.name).toList().indexOf('Madurai'),
          lessThan(r.map((m) => m.name).toList().indexOf('Madurai Colony')));
    });

    test('a town comes before a street of the same relevance, a street before a village', () {
      final r = index().search('ring');
      final kinds = r.map((m) => m.kind).toList();
      expect(kinds.indexOf('town'), lessThan(kinds.indexOf('street')));
      expect(kinds.indexOf('street'), lessThan(kinds.indexOf('village')));
    });

    test('an alternative name matches, and the primary name is what is shown', () {
      final r = index().search('மதுரை');
      expect(r, isNotEmpty);
      expect(r.first.name, 'Madurai');
      expect(index().search('madura').first.name, 'Madurai');
    });

    test('a search with no places still finds streets, as before', () {
      final r = PlaceIndex(pack).search('column street 4');
      expect(r.first.name, 'Column Street 4');
      expect(r.first.kind, 'street');
    });

    test('the nearest comes first among equals, and a limit is respected', () {
      const twins = [
        GazetteerEntry(name: 'Kovil Village', lat: 9.0, lon: 77.0, kind: 'village'),
        GazetteerEntry(name: 'Kovil Village', lat: 12.0, lon: 79.0, kind: 'village'),
      ];
      final idx = PlaceIndex(pack, gazetteer: twins);
      final near = idx.search('kovil', near: (lat: 11.9, lon: 79.1));
      expect(near.first.point.lat, 12.0);
      expect(idx.search('kovil', limit: 1), hasLength(1));
      expect(idx.search('k'), isEmpty, reason: 'fewer than two letters');
    });
  });

  group('highway numbers', () {
    const roads = [
      GazetteerEntry(name: 'NH44', lat: 10, lon: 78, kind: 'town'),
      GazetteerEntry(name: 'Salem Highway (NH-44)', lat: 11, lon: 78, kind: 'town'),
      GazetteerEntry(name: 'NH444', lat: 12, lon: 78, kind: 'town'),
      GazetteerEntry(name: 'Kollam Road (NH744)', lat: 9, lon: 76, kind: 'town'),
    ];

    test('NH 44 finds NH44 and NH-44, and not NH444 or NH744', () {
      final names = PlaceIndex(pack, gazetteer: roads).search('nh 44').map((m) => m.name).toSet();
      expect(names, {'NH44', 'Salem Highway (NH-44)'});
    });

    test('a query that is only words is unchanged', () {
      expect(PlaceIndex(pack, gazetteer: roads).search('salem').map((m) => m.name),
          ['Salem Highway (NH-44)']);
    });
  });
}
