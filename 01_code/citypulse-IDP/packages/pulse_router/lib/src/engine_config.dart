/// Reads `config/hazard_classes.yaml` (already decoded to Dart maps by the
/// caller) into the typed parameters the [RoutingEngine] needs.
///
/// One parser, used by the Flutter app and by `services/router_api`, so the two
/// can never disagree about what the config says (`docs/CONTRACTS.md` §5: the
/// config lives in one place). This package has no YAML dependency; callers
/// decode with `package:yaml` (a `YamlMap` is a `Map`) or `dart:convert`.
library;

import 'package:pulse_router/src/routing_engine.dart';
import 'package:pulse_router/src/travel_profile.dart';

/// Typed view of `config/hazard_classes.yaml`.
class EngineConfig {
  /// Creates a config from already-typed values.
  const EngineConfig({
    required this.hazardClasses,
    required this.userClasses,
    required this.sourceReliability,
    required this.displayNouns,
    this.travelProfiles = const {},
  });

  /// Parses a decoded config document. Missing optional per-class values fall
  /// back to the defaults below; a missing section or a malformed number is a
  /// [FormatException] naming it.
  ///
  /// Defaults: `h_max_mm` 300 and `epsilon` 0.1 (the `flood` row) for classes
  /// that omit them. They only matter for a class that also reports a depth,
  /// and are flagged here because they are not in the YAML for `debris`,
  /// `accident`, `closure`, `heat` and `aqi`.
  factory EngineConfig.fromMap(Map<Object?, Object?> doc) {
    Map<Object?, Object?> section(String key) {
      final v = doc[key];
      if (v is Map) return v.cast<Object?, Object?>();
      throw FormatException('hazard config: section "$key" is missing');
    }

    double number(Object? v, String where) {
      if (v is num) return v.toDouble();
      throw FormatException('hazard config: $where is not a number: $v');
    }

    final classes = <String, HazardClassParams>{};
    final nouns = <String, String>{};
    section('classes').forEach((name, raw) {
      final key = name! as String;
      final m = (raw! as Map).cast<Object?, Object?>();
      classes[key] = HazardClassParams(
        decayTauSeconds: number(m['T_c_seconds'], 'classes.$key.T_c_seconds'),
        severity: number(m['severity'], 'classes.$key.severity'),
        hMaxMm: m['h_max_mm'] == null
            ? 300
            : number(m['h_max_mm'], 'classes.$key.h_max_mm'),
        epsilon: m['epsilon'] == null
            ? 0.1
            : number(m['epsilon'], 'classes.$key.epsilon'),
      );
      final noun = m['display_noun'];
      if (noun is String) nouns[key] = noun;
    });

    final profiles = <String, TravelProfile>{};
    final rawProfiles = doc['travel_profiles'];
    if (rawProfiles != null) {
      if (rawProfiles is! Map) {
        throw const FormatException('hazard config: travel_profiles must be a map');
      }
      rawProfiles.forEach((name, raw) {
        final id = name! as String;
        profiles[id] = TravelProfile.fromMap(
          id,
          (raw as Map?)?.cast<Object?, Object?>() ?? const {},
        );
      });
    }

    final users = <String, UserClassParams>{};
    section('user_classes').forEach((name, raw) {
      final key = name! as String;
      final m = (raw! as Map).cast<Object?, Object?>();
      final profile = (m['profile'] as String?) ?? 'car';
      if (profile != 'car' && !profiles.containsKey(profile)) {
        throw FormatException(
          'hazard config: user_classes.$key.profile "$profile" is not in '
          'travel_profiles',
        );
      }
      users[key] = UserClassParams(
        z: number(m['z'], 'user_classes.$key.z'),
        lambda: number(m['lambda'], 'user_classes.$key.lambda'),
        profile: profile,
      );
    });

    final reliability = <String, double>{};
    section('source_reliability').forEach((name, raw) {
      reliability[name! as String] = number(raw, 'source_reliability.$name');
    });

    return EngineConfig(
      hazardClasses: Map.unmodifiable(classes),
      userClasses: Map.unmodifiable(users),
      sourceReliability: Map.unmodifiable(reliability),
      displayNouns: Map.unmodifiable(nouns),
      travelProfiles: Map.unmodifiable(profiles),
    );
  }

  /// Per-hazard-class constants.
  final Map<String, HazardClassParams> hazardClasses;

  /// Per-user-class `z` and `λ`.
  final Map<String, UserClassParams> userClasses;

  /// `α_c` per source class.
  final Map<String, double> sourceReliability;

  /// `display_noun` per hazard class, for the template renderer.
  final Map<String, String> displayNouns;

  /// Movement profiles by name (`travel_profiles`, ADR-019).
  final Map<String, TravelProfile> travelProfiles;
}
