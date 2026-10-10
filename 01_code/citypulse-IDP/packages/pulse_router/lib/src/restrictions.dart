/// Hard limits on road segments (ADR-032): a segment that breaks a limit is removed from the search, like the
/// chance constraint (ADR-003), instead of being given a larger cost.
///
/// Two kinds of limit, both built from the reports the engine already holds:
/// - **Per travel mode** (`config/hazard_classes.yaml`, `restrictions.profiles`): apply to everyone using that
///   mode, so one anonymous report must not trigger them (PLAN.md section 12): they need a report from a source at
///   least [RestrictionConfig.reliableAt] reliable, or at least [RestrictionRules.minReports] separate reports.
/// - **The traveller's own choice** (for example "Avoid accidents" on the route screen): applies to that one
///   query, so a single report is enough.
///
/// A report counts while its age is at most [RestrictionConfig.windowFactor] times its class's `T_c` (the same
/// "recent" window the data-gap rule uses) and no newer report of the same class on that segment says it has
/// cleared (polarity -1).
///
/// What this is not: a statement that any other road is safe (ADR-011). It removes what was reported; it knows
/// nothing about what was not.
library;

/// The limits one rule set enforces.
class RestrictionRules {
  /// Creates rules. Empty rules restrict nothing.
  const RestrictionRules({
    this.avoidReported = const {},
    this.maxFloodIndex,
    this.minReports = 1,
  });

  /// Reads one rule set from config. [where] names it in errors.
  factory RestrictionRules.fromMap(String where, Map<Object?, Object?> m) {
    final avoid = m['avoid_reported'];
    if (avoid != null && avoid is! List) {
      throw FormatException(
        'hazard config: $where.avoid_reported must be a list',
      );
    }
    final maxIndex = m['max_flood_index'];
    if (maxIndex != null &&
        (maxIndex is! num || maxIndex <= 0 || maxIndex > 1)) {
      throw FormatException(
        'hazard config: $where.max_flood_index must be in (0, 1]',
      );
    }
    final minReports = m['min_reports'] ?? 1;
    if (minReports is! int || minReports < 1) {
      throw FormatException(
        'hazard config: $where.min_reports must be a positive whole number',
      );
    }
    return RestrictionRules(
      avoidReported: {
        for (final c in (avoid as List?) ?? const []) c as String,
      },
      maxFloodIndex: (maxIndex as num?)?.toDouble(),
      minReports: minReports,
    );
  }

  /// Hazard classes whose live reports close a segment (for example `accident`, `closure`).
  final Set<String> avoidReported;

  /// A segment fused as `flood` or `waterlogging`, with at least one live report, is closed when its pessimistic
  /// index reaches this. `null` disables the rule. The index alone (the 2015 map with no report) never closes a road.
  final double? maxFloodIndex;

  /// Separate reports needed when none comes from a reliable source. 1 for the traveller's own choice.
  final int minReports;

  /// Whether these rules restrict nothing.
  bool get isEmpty => avoidReported.isEmpty && maxFloodIndex == null;

  /// A short machine-readable description, for the trace's context facts.
  String describe() => [
    if (avoidReported.isNotEmpty)
      'avoid_reported=${(avoidReported.toList()..sort()).join('+')}',
    if (maxFloodIndex != null) 'max_flood_index=$maxFloodIndex',
    if (!isEmpty) 'min_reports=$minReports',
  ].join(',');
}

/// The `restrictions` section of `config/hazard_classes.yaml`.
class RestrictionConfig {
  /// Creates a config. The default restricts nothing.
  const RestrictionConfig({
    this.byProfile = const {},
    this.windowFactor = 2,
    this.reliableAt = 0.85,
  });

  /// Reads the section. A missing section gives the default (no mode limits).
  factory RestrictionConfig.fromMap(Map<Object?, Object?>? m) {
    if (m == null) return const RestrictionConfig();
    double number(Object? v, String key, double fallback) {
      if (v == null) return fallback;
      if (v is num && v > 0) return v.toDouble();
      throw FormatException(
        'hazard config: restrictions.$key must be a positive number',
      );
    }

    final profiles = <String, RestrictionRules>{};
    final raw = m['profiles'];
    if (raw != null) {
      if (raw is! Map)
        throw const FormatException(
          'hazard config: restrictions.profiles must be a map',
        );
      raw.forEach((name, rules) {
        profiles[name! as String] = RestrictionRules.fromMap(
          'restrictions.profiles.$name',
          (rules as Map?)?.cast<Object?, Object?>() ?? const {},
        );
      });
    }
    return RestrictionConfig(
      byProfile: Map.unmodifiable(profiles),
      windowFactor: number(
        m['report_window_factor'],
        'report_window_factor',
        2,
      ),
      reliableAt: number(m['reliable_source_at'], 'reliable_source_at', 0.85),
    );
  }

  /// Hard limits per travel profile (`car`, `foot`, `bicycle`, `emergency`).
  final Map<String, RestrictionRules> byProfile;

  /// A report counts while its age is at most this many times its class's `T_c`.
  final double windowFactor;

  /// A report from a source at least this reliable is enough on its own for a mode limit.
  final double reliableAt;
}

/// Why one segment is closed to a query. Everything a `BlockingEdge` needs, worked out by the engine.
class RestrictedEdge {
  /// Creates a record.
  const RestrictedEdge({
    required this.rule,
    required this.hazardClass,
    required this.pMean,
    required this.pPessimistic,
    required this.nEff,
    required this.newestReportAgeSeconds,
    required this.sourceClass,
    required this.reportCount,
  });

  /// `avoid_reported` or `max_flood_index`.
  final String rule;

  /// The class of the reports that closed it.
  final String hazardClass;

  /// Belief of that class on the segment, as the engine computes it elsewhere.
  final double pMean;

  /// The traveller's pessimistic index for it.
  final double pPessimistic;

  /// Evidence weight.
  final double nEff;

  /// Age of the newest report of that class, seconds.
  final double newestReportAgeSeconds;

  /// Source class of that newest report.
  final String sourceClass;

  /// Live reports of that class on the segment.
  final int reportCount;
}
