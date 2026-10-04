import 'package:citypulse_app/src/app.dart';
import 'package:citypulse_app/src/core/app_config.dart';
import 'package:citypulse_app/src/core/city.dart';
import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_store.dart';
import 'package:citypulse_app/src/features/map/map_surface.dart';
import 'package:citypulse_app/src/features/map/maplibre_surface.dart';
import 'package:citypulse_app/src/features/settings/settings_screen.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Serve MapLibre GL JS from this site instead of unpkg.com: no third-party
    // request on page load, no visitor address sent to a CDN, and it works from
    // the service-worker cache. A bare path is not a valid import() specifier, so it must
    // start with ./ . The files and their BSD-3 licence are in
    // web/vendor/maplibre-gl (version pinned to the plugin's, see its README).
    MapLibreMap.webLibrarySource = const MapLibreJsSource.urls(
      scriptUrl: './vendor/maplibre-gl/maplibre-gl.mjs',
      styleUrl: './vendor/maplibre-gl/maplibre-gl.css',
    );
  }
  // Licence texts for the bundled fonts and the self-hosted MapLibre library, so the
  // Software licences page lists them with the Dart packages' own.
  LicenseRegistry.addLicense(() async* {
    for (final (names, asset) in const [
      (['Roboto'], 'assets/licenses/Roboto-OFL.txt'),
      (['Noto Sans Tamil'], 'assets/licenses/NotoSansTamil-OFL.txt'),
      (['maplibre-gl-js'], 'assets/licenses/maplibre-gl-js-BSD3.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks(
        names,
        await rootBundle.loadString(asset),
      );
    }
  });
  // Independent start-up reads run together.
  final (packageInfo, prefs) = await (
    PackageInfo.fromPlatform(),
    SharedPreferences.getInstance(),
  ).wait;
  const config = AppConfig();
  final city = await loadCity(rootBundle, config.cityId);
  final detailCities = await loadDetailCities(rootBundle, city);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cityProvider.overrideWithValue(city),
        detailCitiesProvider.overrideWithValue(detailCities),
        appVersionProvider.overrideWithValue(packageInfo.version),
        mapSurfaceBuilderProvider.overrideWithValue(
          maplibreSurfaceBuilder(
            config.mapStyleUrl,
            centre: cityCentre(city),
            zoom: city.initialZoom,
          ),
        ),
      ],
      child: CityPulseApp(
        appVersion: packageInfo.version,
        disclaimerStore: SharedPreferencesDisclaimerStore(),
      ),
    ),
  );
}
