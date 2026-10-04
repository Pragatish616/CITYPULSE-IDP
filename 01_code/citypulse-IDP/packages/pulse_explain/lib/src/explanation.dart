/// `Explanation` and its `verification` object — `docs/CONTRACTS.md` §4.
/// Produced by every explanation tier (Tier 0 template — this package's
/// `renderTemplate`; a future Tier 1 SLM rewriter and cloud path, T4.3/T4.4)
/// and stamped by `verify` (`verifier.dart`, T4.2).
library;

import 'dart:convert';

/// `docs/CONTRACTS.md` §4's `verification` object.
///
/// **Rule-to-field mapping (this task's documented reading, not a silent
/// contract change — see this package's top-level note in
/// `verifier.dart`).** `docs/CONTRACTS.md` §4 names six verifier rules but
/// its worked example only names three per-rule booleans
/// (`numerals_grounded`, `entities_grounded`, `contrastive_valid`, for rules
/// 1–3) alongside the generic `unsupported_claims` list. Rules 4 (hedge on
/// low/stale confidence) and 6 (ADR-011's no-unhedged-safety-claim, added
/// after this example was written) get no dedicated boolean in the schema as
/// written. Rather than widen the wire schema without an ADR, this
/// implementation surfaces rule 4 and rule 6 failures as tagged entries in
/// [unsupportedClaims] (`rule4:...`, `rule6:...`) — [passed] is `true` iff
/// that list is empty, which is equivalent to "every rule passed" whether or
/// not the rule has its own named boolean.
class VerificationResult {
  /// Creates a verification result. Enforces — with a real, non-strippable
  /// check, not an assertion, per this codebase's established convention
  /// for invariants that protect what gets reported as the paper's headline
  /// metric — that the three named booleans agree with the presence of
  /// their own tagged entries in [unsupportedClaims], so a caller can never
  /// end up with a `passed: true` result whose [unsupportedClaims] is
  /// non-empty, or vice versa.
  VerificationResult({
    required this.numeralsGrounded,
    required this.entitiesGrounded,
    required this.contrastiveValid,
    required this.unsupportedClaims,
    required this.fallbackUsed,
    required this.latencyMs,
  }) : passed = unsupportedClaims.isEmpty {
    if (!(latencyMs >= 0)) {
      throw ArgumentError.value(latencyMs, 'latencyMs', 'must be non-negative');
    }
    final hasRule1 = unsupportedClaims.any((c) => c.startsWith('rule1:'));
    final hasRule2 = unsupportedClaims.any((c) => c.startsWith('rule2:'));
    final hasRule3 = unsupportedClaims.any((c) => c.startsWith('rule3:'));
    if (numeralsGrounded == hasRule1) {
      throw ArgumentError(
        'numeralsGrounded=$numeralsGrounded is inconsistent with '
        'unsupportedClaims ${hasRule1 ? "containing" : "not containing"} a '
        'rule1: entry: $unsupportedClaims',
      );
    }
    if (entitiesGrounded == hasRule2) {
      throw ArgumentError(
        'entitiesGrounded=$entitiesGrounded is inconsistent with '
        'unsupportedClaims ${hasRule2 ? "containing" : "not containing"} a '
        'rule2: entry: $unsupportedClaims',
      );
    }
    if (contrastiveValid == hasRule3) {
      throw ArgumentError(
        'contrastiveValid=$contrastiveValid is inconsistent with '
        'unsupportedClaims ${hasRule3 ? "containing" : "not containing"} a '
        'rule3: entry: $unsupportedClaims',
      );
    }
  }

  /// Whether every verifier rule passed. `unsupportedClaims.isEmpty`,
  /// computed once so the two can never drift apart.
  final bool passed;

  /// Rule 1: every numeral in the text is grounded in the trace.
  final bool numeralsGrounded;

  /// Rule 2: every proper noun in the text is grounded in the trace.
  final bool entitiesGrounded;

  /// Rule 3: every comparative claim is supported by the trace.
  final bool contrastiveValid;

  /// One entry per violation found, each prefixed `ruleN:` — see this
  /// class's doc comment. Empty iff [passed].
  final List<String> unsupportedClaims;

  /// Whether this [Explanation] is Tier 0 output shown *because* a
  /// higher-tier candidate failed verification (rule 5) — never whether
  /// this particular text itself failed (a discarded candidate is never
  /// wrapped in an [Explanation] at all, per rule 5: "never show an
  /// unverified explanation").
  final bool fallbackUsed;

  /// Wall-clock cost of computing this result, in milliseconds.
  final double latencyMs;

  /// The `docs/CONTRACTS.md` §4 wire representation.
  Map<String, Object?> toJson() => {
    'passed': passed,
    'numerals_grounded': numeralsGrounded,
    'entities_grounded': entitiesGrounded,
    'contrastive_valid': contrastiveValid,
    'unsupported_claims': unsupportedClaims,
    'fallback_used': fallbackUsed,
    'latency_ms': latencyMs,
  };
}

/// `docs/CONTRACTS.md` §4's `Explanation` object — the text shown to the
/// user plus the audit trail behind it.
class Explanation {
  /// Creates an explanation. [tier] is `0` for the deterministic template
  /// (this package's `renderTemplate`), `1` for the on-device SLM rewriter
  /// (T4.3, not yet built), `2` for the cloud path (T4.4, not yet built).
  const Explanation({
    required this.queryId,
    required this.tier,
    required this.text,
    required this.locale,
    required this.factsUsed,
    required this.verification,
  });

  /// Matches the source `DecisionTrace.queryId`.
  final String queryId;

  /// `0` (template), `1` (on-device SLM), or `2` (cloud).
  final int tier;

  /// The text shown to the user. Never shown unless `verification.passed`.
  final String text;

  /// `"en"` or `"ta"` (`docs/CONTRACTS.md` §4). This package only ever
  /// produces `"en"` — Tamil templates are future work, not silently
  /// claimed here.
  final String locale;

  /// `DecisionTrace` field paths this text drew facts from, e.g.
  /// `"chosen.duration_s"`, `"alternatives[0].blocking_edges[0]"`.
  final List<String> factsUsed;

  /// This text's verifier result.
  final VerificationResult verification;

  /// The `docs/CONTRACTS.md` §4 wire representation.
  Map<String, Object?> toJson() => {
    'query_id': queryId,
    'tier': tier,
    'text': text,
    'locale': locale,
    'facts_used': factsUsed,
    'verification': verification.toJson(),
  };

  /// Canonical, deterministic serialisation.
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
