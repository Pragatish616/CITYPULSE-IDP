/// Which city this build serves (ADR-018).
///
/// The city is chosen at build time with `--dart-define=CITY=<id>` (default: the
/// `default_city` in `config/cities.yaml`) and loaded once at start-up from the
/// bundled copy of that file. Screens read it through [cityProvider]; nothing
/// else in the app names a city.
library;

import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:yaml/yaml.dart';

/// The bundled copy of `config/cities.yaml` (copied by `scripts/sync_data_assets.sh`).
const String kCitiesAsset = 'assets/config/cities.yaml';

/// The city in use. Overridden in `main` and in tests; reading it before that is
/// a programming error.
final cityProvider = Provider<CityConfig>(
  (ref) => throw StateError(
    'cityProvider was not overridden; load the city with loadCity() in main()',
  ),
);

/// Detailed cities served inside the region in use (ADR-022), for example Chennai inside Tamil Nadu.
/// Empty for a plain city.
final detailCitiesProvider = Provider<List<CityConfig>>((ref) => const []);

/// Reads the city [id] (or the file's default when [id] is empty) from [bundle].
Future<CityConfig> loadCity(AssetBundle bundle, String id) async {
  final doc = (loadYaml(await bundle.loadString(kCitiesAsset)) as YamlMap)
      .cast<Object?, Object?>();
  return CityConfig.fromMap(doc, id.isEmpty ? CityConfig.defaultId(doc) : id);
}

/// The detailed cities named by [city].detailRegions, read from the bundled config.
Future<List<CityConfig>> loadDetailCities(
  AssetBundle bundle,
  CityConfig city,
) async {
  if (city.detailRegions.isEmpty) return const [];
  final doc = (loadYaml(await bundle.loadString(kCitiesAsset)) as YamlMap)
      .cast<Object?, Object?>();
  return [for (final id in city.detailRegions) CityConfig.fromMap(doc, id)];
}

/// The initial camera centre for [city].
GeoPoint cityCentre(CityConfig city) =>
    (lat: city.centreLat, lon: city.centreLon);
