/// The route advisor (ADR-021): a small, fast, offline decision model that turns a computed route's
/// facts into typed answers with probabilities, in the style of a "System One" model: structured state
/// in, a fixed set of typed decisions out, all computed in one pass, no text generated.
///
/// What it decides, all from the route's own [DecisionTrace]:
/// - how risky the route is ([RiskLevel]);
/// - what the traveller should do ([AdviceAction]);
/// - how much evidence stands behind that ([EvidenceLevel]);
/// - how clearly the chosen route beats the alternatives ([RouteChoice]).
///
/// **What it is not.** It is not learned and not a language model. Every weight below is a hand-set,
/// documented placeholder (there are no outcome labels to learn from: the 2015 replay showed crowd
/// reports add nothing, ADR-012). The probabilities are model scores, **not measured frequencies**, and
/// the UI must not print them as percentages. Like the rest of the app it never says a road is safe or
/// passable (ADR-011): the mildest verdict is "proceed with care", and weak evidence pulls every answer
/// toward "moderate", never toward "lower risk" (absence of data is not absence of hazard).
///
/// Cost: about a hundred floating-point operations per route, so microseconds on a phone.
library;

import 'dart:math' as math;

import 'decision_trace.dart';
import 'routing_engine.dart' show EventState;

/// How risky the route is, relative to other routes. Never "safe".
enum RiskLevel {
  /// Little flood risk found on the data available.
  lower,

  /// Some risk, or too little data to tell.
  moderate,

  /// Substantial flood risk on part of the route.
  high,
}

/// What the traveller should do. There is deliberately no "safe to go" answer (ADR-011).
enum AdviceAction {
  /// Take the route, staying alert.
  proceedWithCare,

  /// Delay the trip if that is possible.
  wait,

  /// Do not take this route if there is any other way.
  avoid,
}

/// How much data stands behind the advice.
enum EvidenceLevel {
  /// Plenty of recent data.
  strong,

  /// Some recent data.
  some,

  /// Little, old or no data.
  little,
}

/// Why the advice is what it is. The UI turns these into fixed sentences; none carries a number.
enum AdviceReason {
  /// The riskiest street on the route has high flood risk.
  highRiskStreet,

  /// Some streets on the route have flood risk.
  someRiskStreets,

  /// Faster routes through flooded streets were left out.
  floodedAlternativesAvoided,

  /// Little recent data covers the route.
  littleData,

  /// The data is out of date.
  staleData,

  /// No flood event is under way, so the flood map is not applied.
  noEvent,

  /// The route's riskiest street has almost no flood risk in the data held. This says what the data shows;
  /// it is not a statement that the route is safe (ADR-011), and it is shown beside the evidence level.
  noHazardFound,
}

/// The facts the advisor reads. Plain numbers, so the model can be tested without a router.
class RouteFacts {
  /// Creates facts. [worstEdgeP] and [hazardPenaltyRatio] are clamped to 0..1 by the model.
  const RouteFacts({
    required this.worstEdgeP,
    required this.hazardPenaltyRatio,
    required this.confidence,
    required this.dataGapCount,
    required this.userClass,
    required this.eventState,
    this.blockedAlternatives = 0,
    this.candidates = const [],
  });

  /// Builds the facts from a trace. [eventState] is the state the query ran under (not in the trace).
  factory RouteFacts.fromTrace(
    DecisionTrace trace, {
    required EventState eventState,
  }) {
    final chosen = trace.chosen;
    final freeFlow = math.max(chosen.freeFlowDurationSeconds, 1);
    return RouteFacts(
      worstEdgeP: chosen.worstEdgeP,
      hazardPenaltyRatio: chosen.hazardTimePenaltySeconds / freeFlow,
      confidence: trace.confidenceBand,
      dataGapCount: trace.dataGaps.length,
      userClass: trace.userClass,
      eventState: eventState,
      blockedAlternatives: trace.alternatives
          .where((a) => a.rejectedBecause == RejectedBecause.chanceConstraint)
          .length,
      candidates: [
        CandidateFacts(
          routeId: chosen.routeId,
          durationSeconds: chosen.durationSeconds,
          riskScore: _riskScore(
            chosen.worstEdgeP,
            chosen.hazardTimePenaltySeconds / freeFlow,
          ),
        ),
        for (final a in trace.alternatives.take(3))
          CandidateFacts(
            routeId: a.routeId,
            durationSeconds: a.durationSeconds,
            riskScore: a.rejectedBecause == RejectedBecause.chanceConstraint
                ? 1
                : a.blockingEdges
                      .fold<double>(0, (m, e) => math.max(m, e.pPessimistic))
                      .clamp(0.0, 1.0),
          ),
      ],
    );
  }

  /// The pessimistic hazard index of the riskiest street on the route.
  final double worstEdgeP;

  /// Hazard time added to the route, as a fraction of its free-flow time.
  final double hazardPenaltyRatio;

  /// The trace's confidence band.
  final ConfidenceBand confidence;

  /// Number of corridors with no usable evidence.
  final int dataGapCount;

  /// Who is travelling.
  final UserClass userClass;

  /// The flood-event state the query ran under.
  final EventState eventState;

  /// Alternatives the router removed outright (chance constraint).
  final int blockedAlternatives;

  /// The chosen route first, then up to three alternatives.
  final List<CandidateFacts> candidates;
}

/// One candidate route for the choice check.
class CandidateFacts {
  /// Creates a candidate; [riskScore] is 0..1.
  const CandidateFacts({
    required this.routeId,
    required this.durationSeconds,
    required this.riskScore,
  });

  /// The trace's label for the route.
  final String routeId;

  /// Total duration in seconds.
  final double durationSeconds;

  /// 0..1 risk score, same scale as the model's own.
  final double riskScore;
}

/// How clearly the chosen route beats the alternatives.
class RouteChoice {
  /// Creates a choice summary.
  const RouteChoice({required this.chosenProbability, required this.compared});

  /// Probability (a model score) that the chosen route is the best of those compared; 1 when it is
  /// the only one.
  final double chosenProbability;

  /// Number of routes compared, including the chosen one.
  final int compared;
}

/// The advisor's answer.
class Advice {
  /// Creates advice.
  const Advice({
    required this.risk,
    required this.action,
    required this.evidence,
    required this.evidenceScore,
    required this.reasons,
    required this.choice,
  });

  /// Probability over [RiskLevel]; sums to 1.
  final Map<RiskLevel, double> risk;

  /// Probability over [AdviceAction]; sums to 1.
  final Map<AdviceAction, double> action;

  /// The evidence level.
  final EvidenceLevel evidence;

  /// The evidence score, 0..1.
  final double evidenceScore;

  /// At most two reasons, most important first.
  final List<AdviceReason> reasons;

  /// The route-choice check.
  final RouteChoice choice;

  /// The most likely risk level.
  RiskLevel get riskLevel => _argmax(risk);

  /// The most likely action.
  AdviceAction get bestAction => _argmax(action);

  /// The probability of [bestAction]: how decisive the advice is.
  double get decisiveness => action[bestAction]!;
}

T _argmax<T extends Enum>(Map<T, double> m) {
  T? best;
  var bestP = -1.0;
  for (final e in m.entries) {
    if (e.value > bestP) {
      best = e.key;
      bestP = e.value;
    }
  }
  return best!;
}

double _riskScore(double p, double penaltyRatio) {
  final pp = p.isFinite ? p.clamp(0.0, 1.0) : 1.0;
  final ratio = penaltyRatio.isFinite
      ? math.min(1.0, math.max(0.0, penaltyRatio) / 0.5)
      : 1.0;
  return (0.7 * pp + 0.3 * ratio).clamp(0.0, 1.0);
}

/// How much more weight each class gives to high and moderate risk. Placeholders, like `z` and `λ`
/// in `config/hazard_classes.yaml`.
const Map<UserClass, double> sensitivity = {
  UserClass.commuter: 1.0,
  UserClass.cyclist: 1.25,
  UserClass.pedestrian: 1.5,
  UserClass.emergency: 1.6,
};

// Centres and width of the three risk levels on the 0..1 risk score, and what the model believes
// when it has no evidence at all (mostly "moderate": no data is not "lower").
const List<double> _centres = [0.08, 0.40, 0.80];
const double _sigma = 0.17;
const List<double> _noEvidencePrior = [0.15, 0.55, 0.30];

// Utility of each action under each risk level: rows are proceed / wait / avoid, columns lower /
// moderate / high.
const List<List<double>> _utility = [
  [1.0, 0.15, -1.0],
  [0.35, 0.75, 0.30],
  [-0.5, 0.30, 1.0],
];
const double _beta = 4.0;

/// Turns [facts] into [Advice].
Advice advise(RouteFacts facts) {
  final evidenceScore = _evidenceScore(facts);
  final r = _riskScore(facts.worstEdgeP, facts.hazardPenaltyRatio);

  // Risk: soft assignment of the score to the three levels, blended toward the no-evidence prior
  // as evidence thins.
  final w = [
    for (final c in _centres)
      math.exp(-math.pow(r - c, 2) / (2 * _sigma * _sigma)),
  ];
  final wSum = w.fold<double>(0, (a, b) => a + b);
  final risk = [
    for (var i = 0; i < 3; i++)
      evidenceScore * (w[i] / wSum) + (1 - evidenceScore) * _noEvidencePrior[i],
  ];

  // Sensitive travellers weigh moderate and high risk more.
  final s = sensitivity[facts.userClass] ?? 1.0;
  final adj = [risk[0], risk[1] * math.sqrt(s), risk[2] * s];
  final adjSum = adj.fold<double>(0, (a, b) => a + b);
  final pr = [for (final v in adj) v / adjSum];

  // Action: softmax over expected utility.
  final u = [
    for (var a = 0; a < 3; a++)
      _beta *
          (_utility[a][0] * pr[0] +
              _utility[a][1] * pr[1] +
              _utility[a][2] * pr[2]),
  ];
  final uMax = u.reduce(math.max);
  final e = [for (final v in u) math.exp(v - uMax)];
  final eSum = e.fold<double>(0, (a, b) => a + b);

  return Advice(
    risk: {for (var i = 0; i < 3; i++) RiskLevel.values[i]: risk[i]},
    action: {for (var i = 0; i < 3; i++) AdviceAction.values[i]: e[i] / eSum},
    evidence: evidenceScore >= 0.7
        ? EvidenceLevel.strong
        : evidenceScore >= 0.4
        ? EvidenceLevel.some
        : EvidenceLevel.little,
    evidenceScore: evidenceScore,
    reasons: _reasons(facts, r),
    choice: _choice(facts, s),
  );
}

double _evidenceScore(RouteFacts f) {
  final base = switch (f.confidence) {
    ConfidenceBand.high => 1.0,
    ConfidenceBand.moderate => 0.65,
    ConfidenceBand.low => 0.30,
    ConfidenceBand.stale => 0.20,
  };
  var score = base - 0.1 * math.min(f.dataGapCount, 3);
  // With no flood event declared the prior is not applied (ADR-015), so a quiet route says little.
  if (f.eventState == EventState.dry) score *= 0.7;
  return score.clamp(0.05, 1.0);
}

List<AdviceReason> _reasons(RouteFacts f, double r) {
  final out = <AdviceReason>[];
  if (f.worstEdgeP >= 0.5) {
    out.add(AdviceReason.highRiskStreet);
  } else if (f.worstEdgeP >= 0.2) {
    out.add(AdviceReason.someRiskStreets);
  } else if (f.worstEdgeP < 0.05 &&
      f.hazardPenaltyRatio < 0.01 &&
      f.eventState != EventState.dry) {
    // Without this line a verdict of "moderate" on a route with nothing found reads as if the numbers were
    // missing: the verdict comes from thin evidence, and the card should say what was and was not found. Not on
    // a dry day, when the flood map is not applied and "nothing found" would mean nothing.
    out.add(AdviceReason.noHazardFound);
  }
  if (f.blockedAlternatives > 0)
    out.add(AdviceReason.floodedAlternativesAvoided);
  if (f.confidence == ConfidenceBand.stale) {
    out.add(AdviceReason.staleData);
  } else if (f.confidence == ConfidenceBand.low) {
    out.add(AdviceReason.littleData);
  }
  if (f.eventState == EventState.dry) out.add(AdviceReason.noEvent);
  return out.take(2).toList();
}

RouteChoice _choice(RouteFacts f, double s) {
  final c = f.candidates;
  if (c.length < 2)
    return RouteChoice(chosenProbability: 1, compared: math.max(1, c.length));
  // Utility in hours: time lost, plus a risk charge that grows with the traveller's sensitivity.
  final u = [
    for (final x in c) -(x.durationSeconds / 3600) - 2.0 * s * x.riskScore,
  ];
  const temperature = 0.25;
  final uMax = u.reduce(math.max);
  final e = [for (final v in u) math.exp((v - uMax) / temperature)];
  final eSum = e.fold<double>(0, (a, b) => a + b);
  return RouteChoice(chosenProbability: e[0] / eSum, compared: c.length);
}
