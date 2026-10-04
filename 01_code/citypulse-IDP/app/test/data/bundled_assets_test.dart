// Checks the real data bundled into the app (not fixtures). Plain `test`, not
// `testWidgets`, because asset loading is real file I/O.
import 'dart:convert';

import 'package:citypulse_app/src/core/city.dart';
import 'package:citypulse_app/src/features/map/map_screen.dart';
import 'package:citypulse_app/src/features/map/route_card.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled cities.yaml loads, and its default is Chennai', () async {
    final city = await loadCity(rootBundle, '');
    expect(city.id, 'chennai');
    expect(city.hazardLayer, isTrue);
    expect(city.packDir, 'data/packs/2026-10-02');
    final explicit = await loadCity(rootBundle, 'chennai');
    expect(explicit.centreLat, city.centreLat);
    await expectLater(loadCity(rootBundle, 'atlantis'), throwsFormatException);
  });

  test('the bundled pack is the one the default city names', () async {
    final city = await loadCity(rootBundle, '');
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/packs/manifest.json'),
    ) as Map<String, Object?>;
    // The pack folder is named by date; the manifest records the same date.
    expect(city.packDir, endsWith(manifest['built']! as String));
  });

  test('hazard_classes.yaml gives the Tier 0 renderer its nouns', () async {
    final c = ProviderContainer(
      overrides: [assetBundleProvider.overrideWithValue(rootBundle)],
    );
    addTearDown(c.dispose);
    final nouns = await c.read(hazardNounsProvider.future);
    expect(nouns['flood'], 'flooding');
    expect(nouns['waterlogging'], 'waterlogging');
  });

  test('the bundled watchlist is 402 candidates, inside Chennai, and every '
      'one is still marked unverified (no resident has signed off)', () async {
    final c = ProviderContainer(
      overrides: [assetBundleProvider.overrideWithValue(rootBundle)],
    );
    addTearDown(c.dispose);
    final doc = jsonDecode(
      await c.read(watchlistGeoJsonProvider.future),
    ) as Map<String, Object?>;
    final features = (doc['features']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(features, hasLength(402));
    for (final f in features) {
      final coords = ((f['geometry']! as Map)['coordinates']! as List<Object?>)
          .cast<num>();
      expect(coords[0], inInclusiveRange(79.95, 80.35)); // lon
      expect(coords[1], inInclusiveRange(12.75, 13.25)); // lat
      expect(
        (f['properties']! as Map)['verified'],
        isFalse,
        reason: 'T-W1 resident sign-off has not happened (ADR-009)',
      );
    }
  });

  test('the map pack manifest matches the files that were bundled', () async {
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/packs/manifest.json'),
    ) as Map<String, Object?>;
    final files = manifest['files']! as Map<String, Object?>;
    for (final name in ['graph.bin', 'nodes.bin', 'meta.bin']) {
      final bytes = await rootBundle.load('assets/packs/$name');
      expect(
        bytes.lengthInBytes,
        (files[name]! as Map)['bytes'],
        reason: '$name size differs from its manifest entry',
      );
    }
    expect((manifest['counts']! as Map)['edges'], 471240);
  });
}
