import 'dart:math' as math;

/// The logistic function, `σ(x) = 1 / (1 + e^-x)`. Maps log-odds to a
/// probability in `(0, 1)`.
double sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

/// The logit function, `logit(p) = ln(p / (1 - p))`. Maps a probability in
/// `(0, 1)` to log-odds. Used to turn a source-reliability probability
/// `α_c` (`config/hazard_classes.yaml`) into an evidence weight.
double logit(double p) {
  assert(
    p > 0 && p < 1,
    'logit is undefined outside the open interval (0, 1): got $p',
  );
  return math.log(p / (1 - p));
}
