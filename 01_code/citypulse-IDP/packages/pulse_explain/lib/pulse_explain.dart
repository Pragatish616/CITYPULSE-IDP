/// CityPulse AI's explanation layer (`docs/IMPLEMENTATION_PLAN.md` Phase 4):
/// the Tier 0 deterministic template renderer (`T4.1`) and the symbolic
/// verifier every explanation tier must pass (`T4.2`). See
/// `docs/DECISIONS.md` ADR-004 for why the SLM is a rewriter, never a fact
/// source, and `docs/CONTRACTS.md` §4 for the schemas this package
/// implements.
///
/// No I/O, and deliberately depends on nothing but `pulse_router`'s
/// `DecisionTrace` — per `CLAUDE.md`'s "the LLM never invents facts" rule
/// and the `implementer` role's "never let the explanation layers read
/// anything except the `DecisionTrace`."
library;

export 'src/explanation.dart';
export 'src/template_renderer.dart';
export 'src/verifier.dart';
