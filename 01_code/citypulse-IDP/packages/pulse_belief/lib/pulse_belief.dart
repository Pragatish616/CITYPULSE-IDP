/// Pure hazard-belief fusion for CityPulse AI (`docs/IMPLEMENTATION_PLAN.md`
/// T1.2). See `CLAUDE.md` §6 for the model this implements and
/// `docs/DECISIONS.md` ADR-002 for why the pessimistic plug-in exists.
///
/// No I/O: geometry, config loading (`config/hazard_classes.yaml`), and
/// `HazardObservation` parsing all stay outside this package. Callers resolve
/// a `HazardObservation` to a `WeightedObservation` per candidate edge, then
/// call `fuse` and `pessimistic`.
library;

export 'src/beta.dart';
export 'src/beta_belief.dart';
export 'src/fusion.dart';
export 'src/kernel.dart';
export 'src/math_utils.dart';
export 'src/observation.dart';
export 'src/pessimistic.dart';
