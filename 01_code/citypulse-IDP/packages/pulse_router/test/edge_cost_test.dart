import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

void main() {
  group('edgeCost', () {
    test('reduces to free-flow time when p_pessimistic is 0', () {
      final result = edgeCost(
        freeFlowSeconds: 120,
        freeFlowKmh: 40,
        pPessimistic: 0,
        depthMm: 200,
        severity: 0.6,
        lambda: 0.5,
        hMaxMm: 300,
        epsilon: 0.1,
      );
      expect(result.removedByChanceConstraint, isFalse);
      expect(result.costSeconds, equals(120));
    });

    test('the required ADR-003 invariant: w_lambda(e,t) >= tau_0(e,t) on an '
        'ordinary Chennai arterial (v_free ~= 30 km/h) with p_pessimistic > 0, '
        'even at shallow depth where the raw v_free/v_safe ratio is < 1', () {
      const freeFlowSeconds = 200.0;
      final result = edgeCost(
        freeFlowSeconds: freeFlowSeconds,
        freeFlowKmh: 30,
        pPessimistic: 0.6,
        depthMm: 20, // shallow -- v_safe(20mm) is still well above 30 km/h
        severity: 0.6,
        lambda: 0.3,
        hMaxMm: 300,
        epsilon: 0.1,
      );
      expect(result.removedByChanceConstraint, isFalse);
      expect(result.delta, equals(1)); // confirms the clamp actually fired
      expect(result.costSeconds, greaterThanOrEqualTo(freeFlowSeconds));
    });

    test('without the delta clamp this same edge would (wrongly) cost less '
        'than free-flow', () {
      // Demonstrates why the clamp in slowdownDelta is load-bearing: this is
      // exactly the unclamped computation ADR-003 warns about.
      final vSafe = pregnolatoVSafeKmh(20);
      final unclampedDelta = 30 / vSafe;
      expect(unclampedDelta, lessThan(1));
    });

    test('cost increases with p_pessimistic, holding depth fixed', () {
      double costAt(double p) => edgeCost(
        freeFlowSeconds: 100,
        freeFlowKmh: 60,
        pPessimistic: p,
        depthMm: 150,
        severity: 0.6,
        lambda: 0.5,
        hMaxMm: 300,
        epsilon: 0.9,
      ).costSeconds!;

      expect(costAt(0.8), greaterThan(costAt(0.2)));
    });

    test('the chance constraint removes the edge outright, not as a large '
        'finite weight', () {
      final result = edgeCost(
        freeFlowSeconds: 100,
        freeFlowKmh: 40,
        pPessimistic: 1,
        depthMm: 320,
        severity: 1,
        lambda: 1,
        hMaxMm: 300,
        epsilon: 0.1,
      );
      expect(result.removedByChanceConstraint, isTrue);
      expect(result.costSeconds, isNull);
      expect(result.delta, isNull);
    });

    test('does not remove the edge when depth exceeds h_max but '
        'p_pessimistic is below epsilon', () {
      final result = edgeCost(
        freeFlowSeconds: 100,
        freeFlowKmh: 40,
        pPessimistic: 0.05,
        depthMm: 320,
        severity: 1,
        lambda: 1,
        hMaxMm: 300,
        epsilon: 0.1,
      );
      expect(result.removedByChanceConstraint, isFalse);
      expect(result.costSeconds, isNotNull);
    });

    test('does not remove the edge when there is no depth observation, '
        'regardless of p_pessimistic', () {
      final result = edgeCost(
        freeFlowSeconds: 100,
        freeFlowKmh: 40,
        pPessimistic: 1,
        depthMm: null,
        severity: 1,
        lambda: 1,
        hMaxMm: 300,
        epsilon: 0.1,
      );
      expect(result.removedByChanceConstraint, isFalse);
    });

    test('rejects out-of-range inputs', () {
      expect(
        () => edgeCost(
          freeFlowSeconds: 100,
          freeFlowKmh: 40,
          pPessimistic: 1.1,
          depthMm: null,
          severity: 1,
          lambda: 1,
          hMaxMm: 300,
          epsilon: 0.1,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => edgeCost(
          freeFlowSeconds: 100,
          freeFlowKmh: 40,
          pPessimistic: 0.5,
          depthMm: null,
          severity: -1,
          lambda: 1,
          hMaxMm: 300,
          epsilon: 0.1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a NaN p_pessimistic or depth_mm outright -- regression for a '
        '2026-09 security review finding: the chance-constraint check '
        '(depthMm > hMaxMm && pPessimistic >= epsilon) evaluates false for '
        'either operand as NaN, so a corrupted reading used to fail OPEN '
        '(kept a hazardous edge) instead of removing it', () {
      expect(
        () => edgeCost(
          freeFlowSeconds: 100,
          freeFlowKmh: 40,
          pPessimistic: double.nan,
          depthMm: 320, // > hMaxMm below -- would have been removed if valid
          severity: 1,
          lambda: 1,
          hMaxMm: 300,
          epsilon: 0.1,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => edgeCost(
          freeFlowSeconds: 100,
          freeFlowKmh: 40,
          pPessimistic: 1,
          depthMm: double.nan,
          severity: 1,
          lambda: 1,
          hMaxMm: 300,
          epsilon: 0.1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
