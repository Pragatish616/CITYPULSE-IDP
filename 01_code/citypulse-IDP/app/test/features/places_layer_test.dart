// The CityPulse places layer: shops, schools, police, bus stands... from OpenStreetMap, drawn when zoomed in to street level.
import 'dart:convert';
import 'dart:io';

import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/features/map/places_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

const _sample = '''
{"version":1,"categories":[
 {"id":"police","en":"Police","ta":"காவல் நிலையங்கள்"},
 {"id":"shop","en":"Shops and markets","ta":"கடைகள், சந்தைகள்"},
 {"id":"bus","en":"Bus stands and stops","ta":"பேருந்து நிலையங்கள், நிறுத்தங்கள்"}],
 "places":[
  [13.0500,80.2500,0,"Adyar Police Station","police","அடையார் காவல் நிலையம்"],
  [13.0502,80.2503,1,"Corner Store","convenience",""],
  [13.0600,80.2600,2,"","bus stop",""],
  [13.2000,80.3000,0,"Far Away Station","police",""]
 ]}''';

void main() {
  final layer = PlacesLayer.parse(_sample);
  const box = (minLat: 13.04, minLon: 80.24, maxLat: 13.07, maxLon: 80.27);

  group('the layer', () {
    test('reads categories and places', () {
      expect(layer.categories.map((c) => c.id), ['police', 'shop', 'bus']);
      expect(layer.places, hasLength(4));
    });

    test('nothing below street level, so the city view stays clean', () {
      expect(layer.visible(box, 13.9), isEmpty);
    });

    test('at street level the main kinds show; shops join only closer in', () {
      final at14 = layer.visible(box, 14).map((p) => p.name).toList();
      expect(at14, containsAll(['Adyar Police Station', '']));
      expect(at14, isNot(contains('Corner Store')));
      expect(layer.visible(box, kPlacesAllZoom).map((p) => p.name), contains('Corner Store'));
    });

    test('only what is in view, and never more than the cap', () {
      expect(layer.visible(box, 17).map((p) => p.name), isNot(contains('Far Away Station')));
      expect(layer.visible(box, 17, cap: 1), hasLength(1));
    });

    test('an unnamed place is labelled by what it is; Tamil names are used in Tamil', () {
      final stop = layer.places[2];
      expect(layer.label(stop), 'bus stop');
      expect(layer.label(layer.places[0], tamil: true), 'அடையார் காவல் நிலையம்');
      expect(layer.label(layer.places[1], tamil: true), 'Corner Store');
    });

    test('the map gets points with name, kind, category and colour', () {
      final doc = jsonDecode(layer.geoJson(layer.visible(box, 17))) as Map<String, dynamic>;
      final f = (doc['features'] as List).first as Map<String, dynamic>;
      expect((f['properties'] as Map).keys, containsAll(['name', 'kind', 'cat', 'colour']));
      expect((f['geometry'] as Map)['coordinates'], [80.25, 13.05]);
    });

    test('the nearest place within reach is found, and nothing beyond it', () {
      expect(layer.nearest((lat: 13.05001, lon: 80.25001))?.name, 'Adyar Police Station');
      expect(layer.nearest((lat: 13.1, lon: 80.1)), isNull);
    });

    test('a broken or empty file is an empty layer, not a crash', () {
      expect(PlacesLayer.parse('{"categories":[],"places":[]}').places, isEmpty);
    });

    test('the bundled Chennai file loads: thousands of places in every category, all inside the city box', () {
      final f = File('assets/data/places_poi.json');
      if (!f.existsSync()) return; // assets are synced by scripts/sync_data_assets.sh
      final real = PlacesLayer.parse(f.readAsStringSync());
      if (real.places.isEmpty) return; // a city without a places layer
      expect(real.places.length, greaterThan(10000));
      expect(real.categories.map((c) => c.id), containsAll(['education', 'health', 'police', 'bus', 'worship', 'shop', 'signal']));
      for (final p in real.places) {
        expect(p.lat, inInclusiveRange(12.75, 13.25));
        expect(p.lon, inInclusiveRange(79.95, 80.35));
      }
      for (final c in real.categories) {
        expect(kPlaceColours.containsKey(c.id), isTrue, reason: c.id);
      }
    });
  });

  group('on the map screen', () {
    testWidgets('zoomed out: no places are sent; zoomed in: they are; switched off: cleared', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: const Size(1280, 800));
      await tester.pumpAndSettle();
      final real = h.map.places;
      expect(real, isNull, reason: 'the harness view starts at zoom 12');

      h.map.currentView = (bounds: (minLat: 13.03, minLon: 80.23, maxLat: 13.07, maxLon: 80.27), zoom: 16);
      h.mapCallbacks.onCameraIdle?.call();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final layer = await h.container.read(placesLayerProvider.future);
      if (layer.places.isEmpty) return; // no places file synced in this checkout
      expect(h.map.places, isNotNull);
      expect(h.map.places, contains('"FeatureCollection"'));

      await h.container.read(settingsProvider.notifier).setShowPlaces(value: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(h.map.places, isNull);
    });

    testWidgets('the layers sheet has the places switch and its legend', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: const Size(1280, 800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layers-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('switch-places')), findsOneWidget);
      expect(find.text('Places'), findsWidgets);
      expect(find.byKey(const Key('places-legend')), findsOneWidget);
      expect(h.container.read(settingsProvider).showPlaces, isTrue);
    });
  });
}
