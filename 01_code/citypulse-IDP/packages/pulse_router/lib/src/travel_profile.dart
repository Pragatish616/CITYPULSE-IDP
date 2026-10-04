/// How a kind of traveller moves over the road network (ADR-019).
///
/// The map pack stores one set of free-flow speeds, the car's. A walker, a
/// cyclist and an ambulance do not move at those speeds, may not be allowed on
/// every road, and may not be bound by one-way streets. A [TravelProfile]
/// turns the pack's per-edge car speed and road class into the speed *this*
/// traveller has on that edge, or says the edge is closed to them. The router
/// then searches a graph built from those times, so each mode finds its own
/// route and its own duration from the same code.
///
/// Every number in a profile is a **placeholder assumption** chosen for
/// plausibility, not a measurement (`config/hazard_classes.yaml` says so beside
/// each one). There is no machine learning or language model here: route
/// geometry always comes from graph search (CLAUDE.md §3 rule 6).
library;

import 'dart:math' as math;

/// Road class names in the order of the pack's `highway_codes` (format v1;
/// `scripts/build_packs.py` `HIGHWAY_CODES`). Index 0 is "unknown".
const List<String> kHighwayCodes = [
  'unknown',
  'motorway',
  'motorway_link',
  'trunk',
  'trunk_link',
  'primary',
  'primary_link',
  'secondary',
  'secondary_link',
  'tertiary',
  'tertiary_link',
  'unclassified',
  'residential',
];

/// The speed model for one kind of traveller.
class TravelProfile {
  /// Creates a profile. With every argument at its default it is the car
  /// profile: the pack's own speeds, every road, one-way streets obeyed.
  const TravelProfile({
    this.id = 'car',
    this.speedKmh = const {},
    this.defaultSpeedKmh,
    this.speedMultiplier = 1,
    this.speedMultiplierByClass = const {},
    this.maxSpeedKmh,
    this.forbidden = const {},
    this.ignoreOneWay = false,
  });

  /// The car profile.
  static const TravelProfile car = TravelProfile();

  /// Name, for messages and cache keys.
  final String id;

  /// Speed in km/h for specific road classes (keys are [kHighwayCodes] names).
  final Map<String, double> speedKmh;

  /// Fixed speed in km/h for any allowed class not in [speedKmh]. `null` means
  /// "scale the car speed by [speedMultiplier]" instead.
  final double? defaultSpeedKmh;

  /// Factor on the car speed when no fixed speed applies.
  final double speedMultiplier;

  /// Per-class override of [speedMultiplier] (an emergency vehicle gains more
  /// on an arterial road than in a narrow lane where it cannot pass).
  final Map<String, double> speedMultiplierByClass;

  /// Upper limit on the speed, km/h.
  final double? maxSpeedKmh;

  /// Road classes this traveller may not use.
  final Set<String> forbidden;

  /// Whether the traveller may go against a one-way street (a pedestrian can).
  final bool ignoreOneWay;

  /// Whether this profile changes nothing about the pack's own graph.
  bool get isCar =>
      speedKmh.isEmpty &&
      defaultSpeedKmh == null &&
      speedMultiplier == 1 &&
      speedMultiplierByClass.isEmpty &&
      maxSpeedKmh == null &&
      forbidden.isEmpty &&
      !ignoreOneWay;

  /// The traveller's speed on an edge of class [highway] whose car speed is
  /// [carKmh], or `null` when the class is closed to them.
  double? speedOn(String highway, double carKmh) {
    if (forbidden.contains(highway)) return null;
    var v =
        speedKmh[highway] ??
        defaultSpeedKmh ??
        carKmh * (speedMultiplierByClass[highway] ?? speedMultiplier);
    final cap = maxSpeedKmh;
    if (cap != null) v = math.min(v, cap);
    return v;
  }

  /// Parses one entry of `travel_profiles` (already decoded). Unknown keys,
  /// unknown road classes and non-positive numbers are a [FormatException]
  /// that names the entry, so a typo cannot silently change a route.
  factory TravelProfile.fromMap(String id, Map<Object?, Object?> m) {
    const allowed = {
      'speed_kmh',
      'speed_multiplier',
      'speed_multiplier_by_class',
      'max_speed_kmh',
      'forbidden',
      'ignore_oneway',
    };
    for (final k in m.keys) {
      if (!allowed.contains(k)) {
        throw FormatException('travel profile "$id": unknown key "$k"');
      }
    }

    double positive(Object? v, String where) {
      if (v is num && v > 0 && v.isFinite) return v.toDouble();
      throw FormatException('travel profile "$id": $where must be a positive number');
    }

    void checkClass(String name) {
      if (!kHighwayCodes.contains(name)) {
        throw FormatException(
          'travel profile "$id": unknown road class "$name" '
          '(known: ${kHighwayCodes.join(', ')})',
        );
      }
    }

    final speeds = <String, double>{};
    double? fallback;
    final rawSpeeds = m['speed_kmh'];
    if (rawSpeeds != null) {
      if (rawSpeeds is! Map) {
        throw FormatException('travel profile "$id": speed_kmh must be a map');
      }
      rawSpeeds.forEach((k, v) {
        final key = '$k';
        if (key == 'default') {
          fallback = positive(v, 'speed_kmh.default');
        } else {
          checkClass(key);
          speeds[key] = positive(v, 'speed_kmh.$key');
        }
      });
    }

    final forbidden = <String>{};
    final rawForbidden = m['forbidden'];
    if (rawForbidden != null) {
      if (rawForbidden is! List) {
        throw FormatException('travel profile "$id": forbidden must be a list');
      }
      for (final c in rawForbidden) {
        checkClass('$c');
        forbidden.add('$c');
      }
    }

    final byClass = <String, double>{};
    final rawByClass = m['speed_multiplier_by_class'];
    if (rawByClass != null) {
      if (rawByClass is! Map) {
        throw FormatException(
          'travel profile "$id": speed_multiplier_by_class must be a map',
        );
      }
      rawByClass.forEach((k, v) {
        checkClass('$k');
        byClass['$k'] = positive(v, 'speed_multiplier_by_class.$k');
      });
    }

    final multiplier = m['speed_multiplier'];
    final cap = m['max_speed_kmh'];
    final oneWay = m['ignore_oneway'];
    if (oneWay != null && oneWay is! bool) {
      throw FormatException('travel profile "$id": ignore_oneway must be true or false');
    }
    return TravelProfile(
      id: id,
      speedKmh: Map.unmodifiable(speeds),
      defaultSpeedKmh: fallback,
      speedMultiplier: multiplier == null ? 1 : positive(multiplier, 'speed_multiplier'),
      speedMultiplierByClass: Map.unmodifiable(byClass),
      maxSpeedKmh: cap == null ? null : positive(cap, 'max_speed_kmh'),
      forbidden: Set.unmodifiable(forbidden),
      ignoreOneWay: oneWay == true,
    );
  }
}
