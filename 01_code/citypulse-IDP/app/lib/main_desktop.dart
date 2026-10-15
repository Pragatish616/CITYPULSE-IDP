// The desktop test app for the route-question model (ADR-035, PREREGISTRATION_QA.md addendum 5).
//
// The same app as `main.dart` (same planner, same router, same question box), with two differences: the map is drawn with flutter_map
// instead of MapLibre (which has no Windows build; same OpenFreeMap style), and the on-device model is always attached, so the question box shows how each question was read by the rules and by
// the model. It looks for the model file in a `models` folder next to the program (see `qa_model_files.dart`).
//
//   flutter run -d windows -t lib/main_desktop.dart --dart-define=CITY=chennai
import 'package:citypulse_app/src/app.dart';
import 'package:citypulse_app/src/core/app_config.dart';
import 'package:citypulse_app/src/core/city.dart';
import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_store.dart';
import 'package:citypulse_app/src/explain/question_labeler_factory.dart';
import 'package:citypulse_app/src/explain/question_labeler_provider.dart';
import 'package:citypulse_app/src/features/map/flutter_map_surface.dart';
import 'package:citypulse_app/src/features/map/map_surface.dart';
import 'package:citypulse_app/src/features/settings/settings_screen.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (names, asset) in const [
      (['Roboto'], 'assets/licenses/Roboto-OFL.txt'),
      (['Noto Sans Tamil'], 'assets/licenses/NotoSansTamil-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks(
        names,
        await rootBundle.loadString(asset),
      );
    }
  });
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
          flutterMapSurfaceBuilder(
            config.mapStyleUrl,
            centre: cityCentre(city),
            zoom: city.initialZoom,
          ),
        ),
        // The test panel starts open here, so each question's readings are in view.
        qaTraceOpenProvider.overrideWithValue(true),
        // Always attached here, whatever the build flag says: this app exists to test the model.
        questionLabelerProvider.overrideWith((ref) {
          final labeler = createDeviceQuestionLabeler();
          if (labeler != null) {
            ref.onDispose(() => disposeDeviceQuestionLabeler(labeler));
          }
          return labeler;
        }),
      ],
      child: CityPulseApp(
        appVersion: packageInfo.version,
        disclaimerStore: SharedPreferencesDisclaimerStore(),
      ),
    ),
  );
}
