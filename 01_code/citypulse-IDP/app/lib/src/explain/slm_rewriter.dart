/// The rewriter interface both Tier 1 (on-device SLM, T4.3) and Tier 2
/// (cloud, T4.4) implement — `docs/DECISIONS.md` ADR-004: the SLM is "only a
/// rewriter, never a fact source." A rewriter's [SlmRewriter.generate]
/// receives nothing but a [FactSet] (never the raw `DecisionTrace` — see
/// `fact_set.dart`) and returns a candidate sentence or two of prose; the
/// caller (`rewrite_pipeline.dart`'s [attemptRewrite]) is responsible for
/// running that candidate through `pulse_explain`'s `verifyOrFallback`
/// before it is ever shown, per ADR-004 / `docs/CONTRACTS.md` §4 rule 5:
/// "on failure, silently emit Tier 0."
///
/// [SlmRewriter.generate] is explicitly allowed to be slow, to throw, or to
/// return garbage (a hallucinated street name, an invented number) — that is
/// exactly the input space the verifier exists to catch. Nothing about this
/// interface trusts its own output; see `rewrite_pipeline.dart`.
library;

import 'package:citypulse_app/src/explain/fact_set.dart';

/// A candidate-text producer for one query's [FactSet]. Implementations:
/// `FlutterGemmaRewriter` (Tier 1, on-device), `CloudRewriter` (Tier 2,
/// Groq), and `FakeSlmRewriter` (test-only, `app/test/fixtures/`).
abstract class SlmRewriter {
  /// `docs/CONTRACTS.md` §4 `Explanation.tier` this rewriter's *verified*
  /// output should be tagged with — `1` for an on-device SLM, `2` for cloud.
  /// (`0` is reserved for the template renderer and is never a rewriter's
  /// own tier.)
  int get tier;

  /// Produces one candidate rewrite of [factSet]. Must never be given, and
  /// must never itself go looking for, anything but the already-redacted
  /// [FactSet] — not the full `DecisionTrace` (ADR-004).
  Future<String> generate(FactSet factSet);
}
