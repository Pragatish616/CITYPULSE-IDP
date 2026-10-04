/// Special functions for the Beta-posterior pessimistic index (ADR-015).
///
/// Self-contained and dependency-free so the Flutter client and the Dart AOT
/// evaluation CLI evaluate **exactly** the same code (ADR-001). Verified
/// against SciPy 1.18 in `test/beta_test.dart` (`fixtures/beta_scipy.json`).
library;

import 'dart:math' as math;

/// `ln(1 + x)`, accurate for tiny `x` (Dart's `dart:math` has no `log1p`).
/// Used as `log1p(-x)` so a probability near 1 does not lose all precision.
double _log1p(double x) {
  if (x.abs() < 1e-4) {
    // Taylor series; the omitted term is below 1e-17 for |x| < 1e-4.
    return x * (1 - x * (0.5 - x * (1 / 3 - x * 0.25)));
  }
  return math.log(1 + x);
}

/// `ln Γ(x)` for `x > 0`, by the Lanczos approximation (g = 7, n = 9);
/// accurate to about 1e-15 relative error over the range used here.
double lnGamma(double x) {
  if (!(x > 0)) {
    throw ArgumentError.value(x, 'x', 'must be positive');
  }
  const g = 7.0;
  const c = <double>[
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  if (x < 0.5) {
    // Reflection formula.
    return math.log(math.pi / math.sin(math.pi * x)) - lnGamma(1 - x);
  }
  final xm = x - 1;
  var a = c[0];
  final t = xm + g + 0.5;
  for (var i = 1; i < 9; i++) {
    a += c[i] / (xm + i);
  }
  return 0.5 * math.log(2 * math.pi) +
      (xm + 0.5) * math.log(t) -
      t +
      math.log(a);
}

/// Continued-fraction evaluation of the incomplete beta function (modified
/// Lentz's method).
double _betaContinuedFraction(double x, double a, double b) {
  const maxIterations = 500;
  const epsilon = 3e-16;
  const tiny = 1e-300;
  final qab = a + b;
  final qap = a + 1;
  final qam = a - 1;
  var c = 1.0;
  var d = 1 - qab * x / qap;
  if (d.abs() < tiny) d = tiny;
  d = 1 / d;
  var h = d;
  for (var m = 1; m <= maxIterations; m++) {
    final m2 = 2 * m;
    var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < epsilon) break;
  }
  return h;
}

/// The regularised incomplete beta function `I_x(a, b)`, i.e. the CDF of a
/// `Beta(a, b)` variable at `x`.
double betaCdf(double x, double a, double b) {
  if (!(a > 0) || !(b > 0)) {
    throw ArgumentError('Beta parameters must be positive: a=$a, b=$b');
  }
  if (x.isNaN) throw ArgumentError.value(x, 'x', 'must not be NaN');
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final logFront =
      lnGamma(a + b) -
      lnGamma(a) -
      lnGamma(b) +
      a * math.log(x) +
      b * _log1p(-x);
  final front = math.exp(logFront);
  if (x < (a + 1) / (a + b + 2)) {
    return front * _betaContinuedFraction(x, a, b) / a;
  }
  return 1 - front * _betaContinuedFraction(1 - x, b, a) / b;
}

/// The `Beta(a, b)` probability density at `x` in `(0, 1)`.
double betaPdf(double x, double a, double b) {
  if (x <= 0 || x >= 1) return 0;
  return math.exp(
    lnGamma(a + b) -
        lnGamma(a) -
        lnGamma(b) +
        (a - 1) * math.log(x) +
        (b - 1) * _log1p(-x),
  );
}

/// The `q`-quantile of `Beta(a, b)`: the `x` with `I_x(a, b) = q`.
///
/// Safeguarded Newton: the root is kept inside a shrinking bracket and any
/// Newton step that leaves it is replaced by bisection, so it converges for
/// every `a, b > 0` including the `a < 1` priors where the density is
/// unbounded at 0. Typically 4-8 CDF evaluations.
double betaQuantile(double q, double a, double b) {
  if (!(a > 0) || !(b > 0)) {
    throw ArgumentError('Beta parameters must be positive: a=$a, b=$b');
  }
  if (!(q >= 0 && q <= 1)) {
    throw ArgumentError.value(q, 'q', 'must be in [0, 1]');
  }
  if (q == 0) return 0;
  if (q == 1) return 1;

  var lo = 0.0;
  var hi = 1.0;
  final mean = a / (a + b);
  var x = mean.clamp(1e-9, 1 - 1e-9);
  // Relative tolerances: with a < 1 the quantile of a low percentile can be
  // 1e-30 or smaller, where an absolute tolerance would stop far too early.
  for (var i = 0; i < 400; i++) {
    final f = betaCdf(x, a, b) - q;
    if (f == 0) return x;
    if (f > 0) {
      hi = x;
    } else {
      lo = x;
    }
    final pdf = betaPdf(x, a, b);
    var next = pdf > 0 && pdf.isFinite ? x - f / pdf : double.nan;
    if (!(next > lo && next < hi)) next = (lo + hi) / 2;
    if ((next - x).abs() <= 1e-14 * x || (hi - lo) <= 1e-14 * hi) {
      return next;
    }
    x = next;
  }
  return x;
}

/// The standard normal CDF `Φ(z)`, from the Abramowitz & Stegun 7.1.26
/// approximation of `erf` (absolute error below 1.5e-7, far inside the
/// uncertainty of any `z` choice).
double normalCdf(double z) {
  if (z.isNaN) throw ArgumentError.value(z, 'z', 'must not be NaN');
  final sign = z < 0 ? -1.0 : 1.0;
  final x = z.abs() / math.sqrt2;
  const p = 0.3275911;
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  final t = 1.0 / (1.0 + p * x);
  final y =
      1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-x * x);
  return 0.5 * (1.0 + sign * y);
}
