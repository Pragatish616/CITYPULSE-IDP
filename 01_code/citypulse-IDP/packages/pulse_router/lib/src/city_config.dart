/// Which city a build serves (ADR-018): its name, map centre, bounding box,
/// pack location and the few city-specific texts. Read from
/// `config/cities.yaml` (already decoded to Dart maps by the caller, like
/// [EngineConfig]); this package has no YAML dependency.
///
/// Nothing in routing, belief or explanation code depends on a city. A city is
/// data: a pack built from its OpenStreetMap roads, optionally a flood-hazard
/// prior, and the entry parsed here.
library;

/// A text in English with an optional Tamil version; Tamil falls back to English.
class LocalizedText {
  /// Creates a text.
  const LocalizedText({required this.en, this.ta});

  /// English.
  final String en;

  /// Tamil (draft until a native speaker reviews it), if given.
  final String? ta;

  /// The text for [languageCode] (`'ta'` or anything else for English).
  String forLanguage(String languageCode) =>
      languageCode == 'ta' ? (ta ?? en) : en;
}

/// One city.
class CityConfig {
  /// Creates a city.
  const CityConfig({
    required this.id,
    required this.name,
    required this.centreLat,
    required this.centreLon,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.packDir,
    this.placesFile,
    required this.hazardLayer,
    required this.hazardNote,
    required this.aboutData,
    required this.dataCredit,
    this.localContact,
    this.maxSnapMetres = 1500,
    this.initialZoom = 11.5,
    this.detailRegions = const [],
  });

  /// Parses the entry [id] from a decoded `cities.yaml` document. A missing
  /// city, section or number is a [FormatException] naming it. A city with
  /// `hazard_layer: true` must carry its own `hazard_note`, `about_data` and
  /// `data_credit` texts; one without gets honest defaults saying that no
  /// flood-hazard layer is loaded.
  factory CityConfig.fromMap(Map<Object?, Object?> doc, String id) {
    final cities = doc['cities'];
    if (cities is! Map) {
      throw const FormatException('cities config: section "cities" is missing');
    }
    final raw = cities[id];
    if (raw is! Map) {
      throw FormatException(
        'cities config: unknown city "$id" (known: '
        '${cities.keys.join(', ')})',
      );
    }
    final m = raw.cast<Object?, Object?>();

    double number(Map<Object?, Object?> from, String key, String where) {
      final v = from[key];
      if (v is num) return v.toDouble();
      throw FormatException('cities config: $id.$where.$key is not a number');
    }

    Map<Object?, Object?> section(String key) {
      final v = m[key];
      if (v is Map) return v.cast<Object?, Object?>();
      throw FormatException('cities config: $id.$key is missing');
    }

    LocalizedText? text(String key, {required bool required}) {
      final v = m[key];
      if (v == null) {
        if (required) {
          throw FormatException('cities config: $id.$key is missing');
        }
        return null;
      }
      if (v is! Map || v['en'] is! String) {
        throw FormatException('cities config: $id.$key needs an "en" text');
      }
      final ta = v['ta'];
      return LocalizedText(
        en: (v['en']! as String).trim(),
        ta: ta is String ? ta.trim() : null,
      );
    }

    final name = text('name', required: true)!;
    final centre = section('centre');
    final bbox = section('bbox');
    final pack = m['pack'];
    if (pack is! String || pack.isEmpty) {
      throw FormatException('cities config: $id.pack is missing');
    }
    final places = m['places'];
    if (places != null && (places is! String || places.isEmpty)) {
      throw FormatException('cities config: $id.places must be a file path');
    }
    final layer = m['hazard_layer'];
    if (layer is! bool) {
      throw FormatException(
        'cities config: $id.hazard_layer must be true or false',
      );
    }
    final minLat = number(bbox, 'min_lat', 'bbox');
    final maxLat = number(bbox, 'max_lat', 'bbox');
    final minLon = number(bbox, 'min_lon', 'bbox');
    final maxLon = number(bbox, 'max_lon', 'bbox');
    if (!(minLat < maxLat && minLon < maxLon)) {
      throw FormatException('cities config: $id.bbox is empty or inverted');
    }
    var zoom = 11.5;
    final rawZoom = m['initial_zoom'];
    if (rawZoom != null) {
      if (rawZoom is! num || !(rawZoom >= 3 && rawZoom <= 18)) {
        throw FormatException(
          'cities config: $id.initial_zoom must be a number from 3 to 18',
        );
      }
      zoom = rawZoom.toDouble();
    }
    var snap = 1500.0;
    final rawSnap = m['max_snap_metres'];
    if (rawSnap != null) {
      if (rawSnap is! num || !(rawSnap >= 100 && rawSnap <= 100000)) {
        throw FormatException(
          'cities config: $id.max_snap_metres must be a number from 100 to 100000',
        );
      }
      snap = rawSnap.toDouble();
    }
    // Other cities whose detailed packs are served inside this region (ADR-022).
    final rawDetail = m['detail_regions'];
    final detail = <String>[];
    if (rawDetail != null) {
      if (rawDetail is! List ||
          rawDetail.any((e) => e is! String || e.isEmpty || e == id)) {
        throw FormatException(
          'cities config: $id.detail_regions must be a list of other city ids',
        );
      }
      detail.addAll(rawDetail.cast<String>());
    }
    final lat = number(centre, 'lat', 'centre');
    final lon = number(centre, 'lon', 'centre');
    if (lat < minLat || lat > maxLat || lon < minLon || lon > maxLon) {
      throw FormatException('cities config: $id.centre is outside its bbox');
    }

    return CityConfig(
      id: id,
      name: name,
      centreLat: lat,
      centreLon: lon,
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      packDir: pack,
      placesFile: places as String?,
      hazardLayer: layer,
      localContact: text('local_contact', required: false),
      maxSnapMetres: snap,
      initialZoom: zoom,
      detailRegions: List.unmodifiable(detail),
      hazardNote:
          text('hazard_note', required: layer) ?? _noLayerHazardNote,
      aboutData: text('about_data', required: layer) ?? _noLayerAboutData,
      dataCredit: text('data_credit', required: layer) ?? _noLayerDataCredit,
    );
  }

  /// The id of the default city in a decoded document.
  static String defaultId(Map<Object?, Object?> doc) {
    final v = doc['default_city'];
    if (v is String && v.isNotEmpty) return v;
    throw const FormatException('cities config: default_city is missing');
  }

  /// Short id, the key in `cities.yaml`.
  final String id;

  /// Display name.
  final LocalizedText name;

  /// Initial map centre.
  final double centreLat;

  /// Initial map centre.
  final double centreLon;

  /// Bounding box the pack was built for.
  final double minLat;

  /// Bounding box the pack was built for.
  final double maxLat;

  /// Bounding box the pack was built for.
  final double minLon;

  /// Bounding box the pack was built for.
  final double maxLon;

  /// Pack folder, relative to the repository's data root.
  final String packDir;

  /// Optional `places.json` (neighbourhoods and suburbs for search), relative to the repository root. When
  /// absent the router looks for `places.json` inside the pack folder, as region packs carry one.
  final String? placesFile;

  /// Whether a real flood-hazard source is loaded into the pack's prior.
  final bool hazardLayer;

  /// One line for the layers sheet.
  final LocalizedText hazardNote;

  /// The "About the data" paragraph.
  final LocalizedText aboutData;

  /// The data-credit paragraph in the licences screen.
  final LocalizedText dataCredit;

  /// A checked local emergency or control-room line, if the city has one.
  final LocalizedText? localContact;

  /// Zoom the map opens at: about 11.5 for a city, lower for a state (ADR-020).
  final double initialZoom;

  /// How far from the road network a start or end point may be and still be routed, metres. A
  /// city pack covers every street, so 1.5 km; a main-roads-only region pack needs far more because a
  /// village can be many kilometres from the nearest main road (ADR-020).
  final double maxSnapMetres;

  /// Ids of cities whose detailed packs are served inside this region (ADR-022): within one of them
  /// the detailed pack and its flood layer are used, anywhere else this region's own pack.
  final List<String> detailRegions;

  /// Whether the box overlaps the given one.
  bool intersects(double minLat, double minLon, double maxLat, double maxLon) =>
      minLat <= this.maxLat &&
      maxLat >= this.minLat &&
      minLon <= this.maxLon &&
      maxLon >= this.minLon;

  /// Whether the point lies inside the city's bounding box.
  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
}

// Honest defaults for a city with no flood-hazard layer. Tamil is a draft.
const _noLayerHazardNote = LocalizedText(
  en: 'No flood-hazard layer is loaded for this city. The map shows citizen '
      'reports only.',
  ta: 'இந்த நகரத்திற்கு வெள்ள அபாய அடுக்கு ஏற்றப்படவில்லை. வரைபடம் '
      'பொதுமக்களின் புகார்களை மட்டுமே காட்டுகிறது.',
);

const _noLayerAboutData = LocalizedText(
  en: 'Roads come from OpenStreetMap. No flood-hazard layer is loaded for '
      'this city yet, so routes use road speeds and citizen reports only, and '
      'most roads have no information.',
  ta: 'சாலைகள் OpenStreetMap-இலிருந்து வருகின்றன. இந்த நகரத்திற்கு வெள்ள அபாய '
      'அடுக்கு இன்னும் ஏற்றப்படவில்லை; எனவே வழிகள் சாலை வேகங்களையும் '
      'பொதுமக்களின் புகார்களையும் மட்டுமே பயன்படுத்துகின்றன, பெரும்பாலான '
      'சாலைகளுக்குத் தகவல் இல்லை.',
);

const _noLayerDataCredit = LocalizedText(
  en: 'Citizen reports come from users of this app. No flood-hazard dataset is '
      'used for this city.',
  ta: 'குடிமக்கள் அறிக்கைகள் இந்தச் செயலியின் பயனர்களிடமிருந்து வருகின்றன. '
      'இந்த நகரத்திற்கு வெள்ள அபாயத் தரவுத்தொகுப்பு பயன்படுத்தப்படவில்லை.',
);
