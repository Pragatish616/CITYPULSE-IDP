/// Build-time configuration, set with `--dart-define` (never committed
/// secrets: there are none here -- the app holds no API keys, F-16).
///
///   flutter run -d chrome \
///     --dart-define=ROUTER_API_URL=http://localhost:8080 \
///     --dart-define=INGEST_URL=http://localhost:8000
library;

/// Where the app finds its back ends and basemap.
class AppConfig {
  /// Creates a config; the defaults point at a local development stack.
  const AppConfig({
    this.routerApiUrl = const String.fromEnvironment(
      'ROUTER_API_URL',
      defaultValue: 'http://localhost:8080',
    ),
    this.ingestUrl = const String.fromEnvironment(
      'INGEST_URL',
      defaultValue: 'http://localhost:8000',
    ),
    this.cityId = const String.fromEnvironment('CITY'),
    this.mapStyleUrl = const String.fromEnvironment(
      'MAP_STYLE_URL',
      defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
    ),
  });

  /// The city from `config/cities.yaml` this build serves; empty means the file's `default_city`.
  final String cityId;

  /// `services/router_api` root (used by the web app, and by the phone when
  /// it is set to compute on the server).
  final String routerApiUrl;

  /// `server/` (FastAPI) root: reports are posted here and read back.
  final String ingestUrl;

  /// MapLibre style URL. The default is OpenFreeMap's `liberty` style (free,
  /// no key; confirm its terms before launch, PLAN.md §4.1). Do not point this
  /// at `tile.openstreetmap.org` (CLAUDE.md §2) or any Google Maps source.
  final String mapStyleUrl;

  /// Appends [path] to [base] with exactly one slash between them.
  static Uri join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$b/$p');
  }
}
