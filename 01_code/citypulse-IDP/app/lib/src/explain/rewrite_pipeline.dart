/// Wires a [SlmRewriter] into the `pulse_explain` verification pipeline —
/// `docs/DECISIONS.md` ADR-004's Tier ≥ 1 composition: build the fact set,
/// ask the rewriter for a candidate, run it through `verifyOrFallback`
/// (`packages/pulse_explain`), and — this file's own addition, since
/// `verifyOrFallback` only covers a *verification* failure, not a rewriter
/// that never answers at all — bound the whole attempt by a deadline so a
/// slow or hung rewriter can never delay the Tier 0 result the caller
/// already has in hand (`docs/DECISIONS.md` ADR-005: "the local tier already
/// has an answer" when the cloud enrichment's ~1.2 s budget runs out).
///
/// This same deadline-and-fallback shape is used for both tiers (not only
/// the cloud one) — an on-device rewriter that overruns it is exactly the
/// T0.1 "TTFT > ~3 s" failure mode `CLAUDE.md` §4 already anticipates moving
/// the SLM out of the interactive path; this file does not decide that
/// policy, it just guarantees the caller is never blocked past [timeout]
/// either way.
library;

import 'dart:async';

import 'package:citypulse_app/src/explain/fact_set.dart';
import 'package:citypulse_app/src/explain/slm_rewriter.dart';
import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';

/// `docs/DECISIONS.md` ADR-005's cloud enrichment deadline — the default
/// [attemptRewrite] budget.
const Duration kRewriterDeadline = Duration(milliseconds: 1200);

/// Attempts to upgrade [tier0] using [rewriter]. Always returns *some*
/// [Explanation]: [tier0] itself (re-stamped `fallback_used: true`) if
/// [rewriter] throws, times out, or produces text that fails verification;
/// otherwise the verified, higher-tier [Explanation] `verifyOrFallback`
/// builds.
///
/// Never awaits longer than [timeout] — [tier0] is the guaranteed floor this
/// call can never delay past that budget (ADR-005). Callers that must show
/// [tier0] immediately and only *later* swap in an upgrade should not await
/// this inline on their critical rendering path; it is still safe to await
/// inline anywhere a bounded ~1.2 s (or shorter, in tests) pause is
/// acceptable, since [tier0] is always what falls out the other end on any
/// failure.
Future<Explanation> attemptRewrite({
  required DecisionTrace trace,
  required Explanation tier0,
  required SlmRewriter rewriter,
  Map<String, String> hazardDisplayNouns = const {},
  Duration timeout = kRewriterDeadline,
}) async {
  final factSet = FactSet.fromTrace(
    trace,
    hazardDisplayNouns: hazardDisplayNouns,
  );

  String candidateText;
  try {
    candidateText = await rewriter.generate(factSet).timeout(timeout);
  } catch (_) {
    // Timeout, or any generation failure (network error, model/runtime
    // error, an exception the rewriter itself couldn't recover from) --
    // per ADR-004 / CONTRACTS.md §4 rule 5, a rewriter that fails to answer
    // at all is handled exactly like one that answers with unverifiable
    // text: fall back to Tier 0, silently. `verifyOrFallback` only covers
    // the latter case (a candidate that failed verification); this
    // deliberately broad catch covers the former with the same
    // fallback_used signal, since either way the caller must never see a
    // half-finished candidate or a thrown exception from this function.
    return _stampFallback(tier0);
  }

  return verifyOrFallback(
    candidateText: candidateText,
    candidateTier: rewriter.tier,
    candidateFactsUsed: factSet.availableFactPaths,
    trace: trace,
    queryId: trace.queryId,
    tier0Fallback: () => tier0,
    hazardDisplayNouns: hazardDisplayNouns,
  );
}

/// Re-stamps [tier0] with `fallback_used: true` — mirrors
/// `verifyOrFallback`'s own fallback construction
/// (`packages/pulse_explain/lib/src/verifier.dart`), reproduced here rather
/// than calling it, since there is no failing *candidate* to verify in this
/// branch (see [attemptRewrite]'s catch clause: the rewriter never produced
/// text at all).
Explanation _stampFallback(Explanation tier0) => Explanation(
  queryId: tier0.queryId,
  tier: tier0.tier,
  text: tier0.text,
  locale: tier0.locale,
  factsUsed: tier0.factsUsed,
  verification: VerificationResult(
    numeralsGrounded: tier0.verification.numeralsGrounded,
    entitiesGrounded: tier0.verification.entitiesGrounded,
    contrastiveValid: tier0.verification.contrastiveValid,
    unsupportedClaims: tier0.verification.unsupportedClaims,
    fallbackUsed: true,
    latencyMs: tier0.verification.latencyMs,
  ),
);
