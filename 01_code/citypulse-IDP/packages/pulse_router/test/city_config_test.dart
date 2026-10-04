import 'dart:io';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Map<Object?, Object?> _doc(String yaml) =>
    (loadYaml(yaml) as YamlMap).cast<Object?, Object?>();

const _minimal = '''
default_city: testville
cities:
  testville:
    name: { en: Testville }
    centre: { lat: 28.0, lon: 77.0 }
    bbox: { min_lat: 27.9, max_lat: 28.1, min_lon: 76.9, max_lon: 77.1 }
    pack: data/packs/testville
    hazard_layer: false
''';

void main() {
  group('the shipped config/cities.yaml', () {
    final doc = _doc(File('../../config/cities.yaml').readAsStringSync());

    test('has Chennai as the default city with its pinned pack and texts', () {
      final id = CityConfig.defaultId(doc);
      expect(id, 'chennai');
      final c = CityConfig.fromMap(doc, id);
      expect(c.name.en, 'Chennai');
      expect(c.name.forLanguage('ta'), 'சென்னை');
      expect(c.packDir, 'data/packs/2026-10-02');
      expect(c.hazardLayer, isTrue);
      expect(c.contains(13.0419, 80.2339), isTrue, reason: 'T. Nagar');
      expect(c.contains(28.6, 77.2), isFalse);
      expect(c.localContact!.en, contains('1913'));
      expect(c.aboutData.en, contains('2015'));
      expect(c.aboutData.en, isNot(contains('\n')));
    });
  });

  group('regions (ADR-020)', () {
    final doc = _doc(File('../../config/cities.yaml').readAsStringSync());

    test('Tamil Nadu is a main-roads region: wide snap radius, state-level zoom, no hazard layer',
        () {
      final c = CityConfig.fromMap(doc, 'tamil_nadu');
      expect(c.hazardLayer, isFalse);
      expect(c.maxSnapMetres, 15000);
      expect(c.initialZoom, lessThan(9));
      expect(c.contains(13.0827, 80.2707), isTrue, reason: 'Chennai');
      expect(c.contains(9.9252, 78.1198), isTrue, reason: 'Madurai');
      expect(c.contains(28.6, 77.2), isFalse, reason: 'Delhi');
      expect(c.packDir, startsWith('data/packs/tamil_nadu-'));
    });

    test('Chennai keeps the city defaults', () {
      final c = CityConfig.fromMap(doc, 'chennai');
      expect(c.maxSnapMetres, 1500);
      expect(c.initialZoom, 11.5);
    });

    test('Tamil Nadu names Chennai as its detailed region; Chennai names none', () {
      expect(CityConfig.fromMap(doc, 'tamil_nadu').detailRegions, ['chennai']);
      expect(CityConfig.fromMap(doc, 'chennai').detailRegions, isEmpty);
    });

    test('detail_regions must be a list of other city ids', () {
      for (final bad in [
        'detail_regions: chennai',
        'detail_regions: [testville]',
        'detail_regions: [3]',
        'detail_regions: [""]',
      ]) {
        final yaml = _minimal.replaceFirst(
          'hazard_layer: false',
          'hazard_layer: false\n    $bad',
        );
        expect(() => CityConfig.fromMap(_doc(yaml), 'testville'), throwsFormatException, reason: bad);
      }
    });

    test('a box overlap test finds the cities that a map view touches', () {
      final c = CityConfig.fromMap(doc, 'chennai');
      expect(c.intersects(12.9, 80.1, 13.1, 80.3), isTrue);
      expect(c.intersects(9.8, 77.9, 10.1, 78.3), isFalse);
    });

    test('a nonsense snap radius or zoom is refused', () {
      for (final bad in [
        'max_snap_metres: 5',
        'max_snap_metres: 9999999',
        'max_snap_metres: far',
        'initial_zoom: 40',
        'initial_zoom: close',
      ]) {
        final yaml = _minimal.replaceFirst(
          'hazard_layer: false',
          'hazard_layer: false\n    $bad',
        );
        expect(() => CityConfig.fromMap(_doc(yaml), 'testville'), throwsFormatException, reason: bad);
      }
    });
  });

  group('a city without a hazard layer', () {
    test('parses with honest defaults and no local contact', () {
      final c = CityConfig.fromMap(_doc(_minimal), 'testville');
      expect(c.hazardLayer, isFalse);
      expect(c.localContact, isNull);
      expect(c.hazardNote.en, contains('No flood-hazard layer'));
      expect(c.aboutData.en, contains('No flood-hazard layer'));
      // Tamil falls back to English when a city gives none.
      expect(c.name.forLanguage('ta'), 'Testville');
    });
  });

  group('bad entries are FormatExceptions that name the problem', () {
    test('unknown city lists the known ones', () {
      expect(
        () => CityConfig.fromMap(_doc(_minimal), 'atlantis'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('atlantis'), contains('testville')),
          ),
        ),
      );
    });

    test('a hazard layer needs its own texts', () {
      final yaml = _minimal.replaceFirst(
        'hazard_layer: false',
        'hazard_layer: true',
      );
      expect(
        () => CityConfig.fromMap(_doc(yaml), 'testville'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('hazard_note'),
          ),
        ),
      );
    });

    test('an inverted box and a centre outside the box are refused', () {
      expect(
        () => CityConfig.fromMap(
          _doc(_minimal.replaceFirst('min_lat: 27.9', 'min_lat: 29.0')),
          'testville',
        ),
        throwsFormatException,
      );
      expect(
        () => CityConfig.fromMap(
          _doc(_minimal.replaceFirst('lat: 28.0', 'lat: 35.0')),
          'testville',
        ),
        throwsFormatException,
      );
    });

    test('a non-boolean hazard_layer and a missing pack are refused', () {
      expect(
        () => CityConfig.fromMap(
          _doc(_minimal.replaceFirst('hazard_layer: false', 'hazard_layer: no thanks')),
          'testville',
        ),
        throwsFormatException,
      );
      expect(
        () => CityConfig.fromMap(
          _doc(_minimal.replaceFirst('pack: data/packs/testville', '')),
          'testville',
        ),
        throwsFormatException,
      );
    });
  });
}
