/// Thinning a long route for the map (ADR-020).
///
/// A route across a state has tens of thousands of nodes. The map cannot show
/// more detail than a pixel, and sending and drawing all of them costs time on
/// the network, in JSON parsing and in the renderer. [simplifyPath] keeps a
/// subset of the points (always the first and the last) such that every
/// dropped point lies within a stated distance of the line that replaces it.
///
/// The route the router chose and its length and duration are untouched; only
/// the polyline handed to the screen is thinner.
library;

import 'dart:math' as math;

/// Same shape as `GeoPoint` in the engine; repeated so this file has no imports of its own.
typedef _Point = ({double lat, double lon});


/// Returns [points] unchanged when it has at most [maxPoints]; otherwise a
/// subsequence of at most [maxPoints] points (endpoints kept) found with the
/// Douglas-Peucker rule. The tolerance starts at [startToleranceMetres] and is
/// raised by 60% until the result is small enough, so a short route is never
/// coarsened more than needed.
///
/// Distances use a local flat projection around the route's middle, which is
/// accurate to well under a metre over the few hundred kilometres of a state.
List<_Point> simplifyPath(
  List<_Point> points, {
  required int maxPoints,
  double startToleranceMetres = 2,
}) {
  if (maxPoints < 2) throw ArgumentError.value(maxPoints, 'maxPoints');
  if (points.length <= maxPoints) return points;

  final midLat = points[points.length ~/ 2].lat;
  final kx = 111320 * math.cos(midLat * math.pi / 180);
  const ky = 110574.0;
  final xs = [for (final p in points) p.lon * kx];
  final ys = [for (final p in points) p.lat * ky];

  var tolerance = startToleranceMetres;
  while (true) {
    final keep = _douglasPeucker(xs, ys, tolerance);
    if (keep.length <= maxPoints || tolerance > 5000) {
      return [for (final i in keep) points[i]];
    }
    tolerance *= 1.6;
  }
}

/// Indices kept by Douglas-Peucker, in order. Iterative: a recursive version
/// would overflow the stack on a 50,000-point route.
List<int> _douglasPeucker(List<double> xs, List<double> ys, double tolerance) {
  final n = xs.length;
  final keep = List<bool>.filled(n, false);
  keep[0] = true;
  keep[n - 1] = true;
  final stack = <(int, int)>[(0, n - 1)];
  while (stack.isNotEmpty) {
    final (first, last) = stack.removeLast();
    if (last <= first + 1) continue;
    final ax = xs[first];
    final ay = ys[first];
    final dx = xs[last] - ax;
    final dy = ys[last] - ay;
    final len2 = dx * dx + dy * dy;
    var worst = -1.0;
    var worstIndex = -1;
    for (var i = first + 1; i < last; i++) {
      final double d;
      if (len2 == 0) {
        final ex = xs[i] - ax;
        final ey = ys[i] - ay;
        d = math.sqrt(ex * ex + ey * ey);
      } else {
        var t = ((xs[i] - ax) * dx + (ys[i] - ay) * dy) / len2;
        t = t.clamp(0.0, 1.0);
        final ex = xs[i] - (ax + t * dx);
        final ey = ys[i] - (ay + t * dy);
        d = math.sqrt(ex * ex + ey * ey);
      }
      if (d > worst) {
        worst = d;
        worstIndex = i;
      }
    }
    if (worst > tolerance) {
      keep[worstIndex] = true;
      stack
        ..add((first, worstIndex))
        ..add((worstIndex, last));
    }
  }
  return [
    for (var i = 0; i < n; i++)
      if (keep[i]) i,
  ];
}
