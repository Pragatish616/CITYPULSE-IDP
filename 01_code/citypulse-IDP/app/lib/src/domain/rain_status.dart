/// What the router service says about satellite rain and why the flood-event state is what it is (ADR-027).
///
/// Read from `GET /event-state`. The app never computes any of this; it only shows it. A missing or unreadable answer is `null`
/// upstream, never a "no rain" reading: no data is not dry weather (ADR-011).
library;

import 'package:pulse_router/pulse_router.dart' show EventState;

/// The satellite rain reading behind the state.
class RainReading {
  /// Creates a reading.
  const RainReading({
    required this.asOf,
    required this.dataAgeMinutes,
    required this.stale,
    required this.accumulationMm,
    required this.peakRateMmH,
    required this.intensityClass,
  });

  /// Time of the satellite image.
  final DateTime asOf;

  /// How old the image was when the service answered, minutes.
  final int dataAgeMinutes;

  /// The service's flag: the data is out of date or could not be refreshed.
  final bool stale;

  /// Area-mean rain over the last three hours, mm.
  final double accumulationMm;

  /// Strongest single cell over the last three hours, mm/h.
  final double peakRateMmH;

  /// The newest image's descriptive band: `none`, `light`, `moderate`, `heavy` or `violent`.
  final String intensityClass;

  /// True when something fell in the last three hours or the newest image shows rain.
  bool get isWet => intensityClass != 'none' || accumulationMm >= 0.1;
}

/// What the rain forecast says about the next 12 hours (ADR-029). Present only when the service has the forecast switched on.
class ForecastReading {
  /// Creates a reading.
  const ForecastReading({required this.trusted, this.maxMm, this.windowEnd});

  /// Whether the service is using the forecast now (recent and complete enough).
  final bool trusted;

  /// The largest three-hour area-mean amount expected in the next 12 hours, mm.
  final double? maxMm;

  /// When that three-hour window ends.
  final DateTime? windowEnd;
}

/// The event state with its mode, source and rain reading.
class RainStatus {
  /// Creates a status.
  const RainStatus({
    required this.state,
    required this.mode,
    required this.source,
    required this.reason,
    this.rain,
    this.forecast,
  });

  /// Reads the service's JSON. Returns `null` for anything that is not a usable status, so a changed or broken answer shows nothing
  /// rather than something wrong. The rain part is optional (it is absent before the first reading, and in `fixed` mode).
  static RainStatus? tryParse(Object? json) {
    if (json is! Map) return null;
    final stateName = json['event_state'];
    if (stateName is! String) return null;
    final EventState state;
    try {
      state = EventState.parse(stateName);
    } on ArgumentError {
      return null;
    }
    RainReading? rain;
    final r = json['rain'];
    if (r is Map) {
      final asOf = DateTime.tryParse('${r['as_of']}');
      final age = r['data_age_minutes'];
      final acc = r['accumulation_3h_mm'];
      final peak = r['peak_rate_mm_h'];
      if (asOf != null &&
          age is num &&
          acc is num &&
          peak is num &&
          age >= 0 &&
          acc >= 0 &&
          peak >= 0) {
        final cls = r['intensity_class_now'];
        rain = RainReading(
          asOf: asOf.toUtc(),
          dataAgeMinutes: age.round(),
          stale: r['stale'] == true,
          accumulationMm: acc.toDouble(),
          peakRateMmH: peak.toDouble(),
          intensityClass: cls is String ? cls : 'unknown',
        );
      }
    }
    ForecastReading? forecast;
    final f = json['forecast'];
    if (f is Map && f['trusted'] is bool) {
      final max = f['max_3h_area_mean_mm_next_12h'];
      forecast = ForecastReading(
        trusted: f['trusted'] as bool,
        maxMm: max is num && max.isFinite && max >= 0 ? max.toDouble() : null,
        windowEnd: DateTime.tryParse('${f['window_end']}')?.toUtc(),
      );
    }
    String text(String key, String fallback) =>
        json[key] is String ? json[key] as String : fallback;
    return RainStatus(
      state: state,
      mode: text('mode', 'unknown'),
      source: text('source', 'unknown'),
      reason: text('reason', ''),
      rain: rain,
      forecast: forecast,
    );
  }

  /// The state in force.
  final EventState state;

  /// `auto`, `manual` or `fixed`.
  final String mode;

  /// `rain`, `forecast`, `manual`, `fallback` or `configured`.
  final String source;

  /// The service's own sentence (English only; the app builds its own words from the fields).
  final String reason;

  /// The rain reading, if the service has one.
  final RainReading? rain;

  /// The forecast, if the service has the forecast input switched on (ADR-029).
  final ForecastReading? forecast;
}
