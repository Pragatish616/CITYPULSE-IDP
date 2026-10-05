/// The flood-event state: set from satellite rain by default, with a human override (ADR-027).
///
/// The state (`dry`, `watch`, `active`) decides whether the static GCC hazard prior is applied (ADR-015, F-09). This file holds
/// the rule and the bookkeeping; `rain_sync.dart` feeds it; `api.dart` shows it and lets an operator override it.
///
/// Modes:
/// - `auto`: the rain rule decides (a rain source is configured and nobody has overridden it).
/// - `manual`: an operator set the state; it wins until cleared or until its optional time is up.
/// - `fixed`: no rain source is configured, so the configured `EVENT_STATE` applies (the behaviour before ADR-027).
///
/// The numbers in [EventRule] are placeholders fixed in ADR-027 before any trial. They are not fitted to Chennai floods.
library;

import 'package:pulse_router/pulse_router.dart' show EventState;

/// What the rain context says, as the rule needs it. Built from the report server's `GET /context/rain`.
class RainSignal {
  /// Creates a signal.
  const RainSignal({
    required this.asOf,
    required this.dataAgeMinutes,
    required this.stale,
    required this.accumulationMm,
    required this.peakRateMmH,
    required this.nowPeakMmH,
    required this.intensityClass,
    this.slicesMissing = 0,
  });

  /// Reads the report server's JSON. Throws [FormatException] if a needed field is missing or not a sensible number, so a changed
  /// or broken feed is a failure, never a silent zero.
  factory RainSignal.fromJson(Map<String, Object?> json) {
    double number(Object? v, String name) {
      if (v is num && v.isFinite && v >= 0) return v.toDouble();
      throw FormatException(
        'rain context: "$name" is missing or not a non-negative number',
      );
    }

    final asOfText = json['as_of'];
    final asOf = asOfText is String ? DateTime.tryParse(asOfText) : null;
    if (asOf == null)
      throw const FormatException(
        'rain context: "as_of" is missing or not a time',
      );
    final now = json['now'];
    final recent = json['recent'];
    if (now is! Map || recent is! Map)
      throw const FormatException('rain context: "now" or "recent" is missing');
    final used = recent['slices_used'];
    if (used is! num || used < 1)
      throw const FormatException('rain context: no images were used');
    final cls = now['intensity_class'];
    return RainSignal(
      asOf: asOf.toUtc(),
      dataAgeMinutes: number(json['data_age_minutes'], 'data_age_minutes'),
      stale: json['stale'] == true,
      accumulationMm: number(
        recent['area_mean_accumulation_mm'],
        'recent.area_mean_accumulation_mm',
      ),
      peakRateMmH: number(recent['peak_rate_mm_h'], 'recent.peak_rate_mm_h'),
      nowPeakMmH: number(now['peak_rate_mm_h'], 'now.peak_rate_mm_h'),
      intensityClass: cls is String ? cls : 'unknown',
      slicesMissing: (recent['slices_missing'] is num)
          ? (recent['slices_missing']! as num).toInt()
          : 0,
    );
  }

  /// Time of the newest satellite image.
  final DateTime asOf;

  /// How old that image was when the report server answered, minutes.
  final double dataAgeMinutes;

  /// The report server's own flag: the data is old or a refresh failed.
  final bool stale;

  /// Area-mean rain over the last three hours, mm.
  final double accumulationMm;

  /// Highest single-cell rate in the last three hours, mm/h.
  final double peakRateMmH;

  /// Highest single-cell rate in the newest image, mm/h.
  final double nowPeakMmH;

  /// The newest image's descriptive band (`none`, `light`, `moderate`, `heavy`, `violent`).
  final String intensityClass;

  /// Older images that could not be read (they make the accumulation an underestimate).
  final int slicesMissing;

  /// For `GET /event-state`.
  Map<String, Object?> toJson() => {
    'as_of': asOf.toIso8601String(),
    'data_age_minutes': dataAgeMinutes.round(),
    'stale': stale,
    'accumulation_3h_mm': accumulationMm,
    'peak_rate_mm_h': peakRateMmH,
    'intensity_class_now': intensityClass,
    if (slicesMissing > 0) 'images_missing': slicesMissing,
  };
}

/// The rule of ADR-027. Placeholders, fixed before any trial.
abstract final class EventRule {
  /// `active` when the three-hour area-mean rain reaches this (about IMD's "very heavy" daily rate held for three hours).
  static const double activeAccumulationMm = 15;

  /// `active` when any cell reaches this rate, mm/h (a round placeholder).
  static const double activePeakMmH = 25;

  /// `watch` when the three-hour area-mean rain reaches this (about IMD's "heavy" daily rate held for three hours).
  static const double watchAccumulationMm = 8;

  /// `watch` when any cell reaches this rate, mm/h (the lower bound of the "heavy" hourly band).
  static const double watchPeakMmH = 7.6;

  /// After a reading at `active`, stay `active` this long (counted from when the service saw it).
  static const Duration activeHold = Duration(hours: 6);

  /// After a reading at `watch` or higher, stay at least `watch` this long (counted from when the service saw it).
  static const Duration watchHold = Duration(hours: 12);

  /// Rain data older than this, or no successful poll for this long, means the rule is not trusted and the configured state applies.
  static const Duration staleAfter = Duration(hours: 12);

  /// The level one reading gives, before holds.
  static EventState levelOf(RainSignal s) {
    if (s.accumulationMm >= activeAccumulationMm ||
        s.peakRateMmH >= activePeakMmH)
      return EventState.active;
    if (s.accumulationMm >= watchAccumulationMm ||
        s.peakRateMmH >= watchPeakMmH)
      return EventState.watch;
    return EventState.dry;
  }
}

/// What `GET /event-state` reports.
class EventStatus {
  /// Creates a status.
  const EventStatus({
    required this.state,
    required this.mode,
    required this.source,
    required this.reason,
    required this.since,
    this.rain,
    this.manualUntil,
  });

  /// The state in force.
  final EventState state;

  /// `auto`, `manual` or `fixed`.
  final String mode;

  /// Where the state came from: `rain`, `manual`, `fallback` or `configured`.
  final String source;

  /// A sentence saying why, with the numbers.
  final String reason;

  /// When the state last changed.
  final DateTime since;

  /// The latest rain reading, if any.
  final RainSignal? rain;

  /// When a time-limited override ends, if one is set.
  final DateTime? manualUntil;

  /// JSON for the API. `event_state` is the field existing clients read.
  Map<String, Object?> toJson() => {
    'event_state': state.name,
    'mode': mode,
    'source': source,
    'reason': reason,
    'since': since.toUtc().toIso8601String(),
    if (manualUntil != null)
      'override_until': manualUntil!.toUtc().toIso8601String(),
    'rain': rain?.toJson(),
  };
}

/// Holds the event state and decides it. Not thread-safe by design: the service is single-isolate.
class EventStateController {
  /// Creates the controller. [configured] is the `EVENT_STATE` setting, used as the fallback and when no rain source exists.
  /// [apply] is called whenever the state in force changes, including once at the start.
  EventStateController({
    required this.configured,
    required this.hasRainSource,
    required void Function(EventState) apply,
    DateTime Function()? now,
  }) : _apply = apply,
       _now = now ?? (() => DateTime.now().toUtc()) {
    _since = _now();
    _recompute();
  }

  /// The configured state.
  final EventState configured;

  /// Whether a rain source is configured (otherwise the mode is `fixed`).
  final bool hasRainSource;

  final void Function(EventState) _apply;
  final DateTime Function() _now;

  EventState? _applied;
  late DateTime _since;
  EventStatus? _status;

  EventState? _manual;
  DateTime? _manualSetAt;
  DateTime? _manualUntil;

  RainSignal? _signal;
  DateTime? _lastSuccess;
  DateTime? _lastFailure;
  String? _lastFailureNote;
  DateTime? _seenActive;
  DateTime? _seenWatch;

  /// A poll succeeded. Holds are only extended by a reading with a NEW satellite time, so polling the same old image again does not
  /// keep an old reading alive.
  void onRain(RainSignal s) {
    final now = _now();
    final isNew = _signal == null || s.asOf != _signal!.asOf;
    _signal = s;
    _lastSuccess = now;
    _lastFailure = null;
    if (isNew) {
      final level = EventRule.levelOf(s);
      if (level == EventState.active) {
        _seenActive = now;
        _seenWatch = now;
      } else if (level == EventState.watch) {
        _seenWatch = now;
      }
    }
    _recompute();
  }

  /// A poll failed (network, bad JSON, 503). The last reading is kept until it is too old to trust.
  void onRainFailure(Object error) {
    _lastFailure = _now();
    _lastFailureNote = error.runtimeType.toString();
    _recompute();
  }

  /// An operator sets the state. [hold] limits how long it wins; `null` means until cleared.
  void setManual(EventState state, {Duration? hold}) {
    final now = _now();
    _manual = state;
    _manualSetAt = now;
    _manualUntil = hold == null ? null : now.add(hold);
    _recompute();
  }

  /// Clears an override and returns to the rain rule. False if there is no rain source to return to.
  bool resumeAuto() {
    if (!hasRainSource) return false;
    _manual = null;
    _manualUntil = null;
    _manualSetAt = null;
    _recompute();
    return true;
  }

  /// Re-evaluates with the current time (holds and overrides can run out between polls).
  void refresh() => _recompute();

  /// The state and why.
  EventStatus status() {
    _recompute();
    return _status!;
  }

  void _recompute() {
    final now = _now();
    if (_manual != null &&
        _manualUntil != null &&
        !now.isBefore(_manualUntil!)) {
      _manual = null;
      _manualUntil = null;
      _manualSetAt = null;
    }
    final EventState state;
    final String mode;
    final String source;
    final String reason;
    if (_manual != null) {
      state = _manual!;
      mode = 'manual';
      source = 'manual';
      reason =
          'Set by an operator at ${_manualSetAt!.toUtc().toIso8601String()}'
          '${_manualUntil != null ? ' until ${_manualUntil!.toUtc().toIso8601String()}' : ' until cleared'}; '
          'the rain rule is not being used.';
    } else if (!hasRainSource) {
      state = configured;
      mode = 'fixed';
      source = 'configured';
      reason = 'No rain source is configured, so the configured state applies.';
    } else {
      mode = 'auto';
      final s = _signal;
      final ok = _lastSuccess;
      final trusted =
          s != null &&
          ok != null &&
          !s.stale &&
          now.difference(ok) <= EventRule.staleAfter;
      if (!trusted) {
        state = configured;
        source = 'fallback';
        reason = s == null
            ? 'No rain reading has been received yet${_failureSuffix()}, so the configured state (${configured.name}) applies.'
            : 'The rain data is older than ${EventRule.staleAfter.inHours} hours or could not be refreshed${_failureSuffix()}, '
                  'so the configured state (${configured.name}) applies.';
      } else if (_seenActive != null &&
          now.difference(_seenActive!) <= EventRule.activeHold) {
        state = EventState.active;
        source = 'rain';
        reason = _rainReason(
          s,
          'rain reached the active level within the last ${EventRule.activeHold.inHours} hours',
        );
      } else if (_seenWatch != null &&
          now.difference(_seenWatch!) <= EventRule.watchHold) {
        state = EventState.watch;
        source = 'rain';
        reason = _rainReason(
          s,
          'rain reached the watch level within the last ${EventRule.watchHold.inHours} hours',
        );
      } else {
        state = EventState.dry;
        source = 'rain';
        reason = _rainReason(
          s,
          'below the watch level, and none at that level in the last ${EventRule.watchHold.inHours} hours',
        );
      }
    }
    if (_applied != state) {
      _applied = state;
      _since = now;
      _apply(state);
    }
    _status = EventStatus(
      state: state,
      mode: mode,
      source: source,
      reason: reason,
      since: _since,
      rain: _signal,
      manualUntil: _manualUntil,
    );
  }

  String _failureSuffix() =>
      _lastFailure == null ? '' : ' (last poll failed: $_lastFailureNote)';

  String _rainReason(RainSignal s, String why) {
    final age = (s.dataAgeMinutes / 60).toStringAsFixed(1);
    final miss = s.slicesMissing > 0
        ? ', ${s.slicesMissing} older image(s) unreadable'
        : '';
    return 'Satellite rain, newest image $age h old: ${s.accumulationMm.toStringAsFixed(1)} mm in the last 3 h (area mean), '
        'peak ${s.peakRateMmH.toStringAsFixed(1)} mm/h$miss; $why.';
  }
}
