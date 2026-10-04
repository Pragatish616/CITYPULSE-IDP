import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

void main() {
  group('pregnolatoVSafeKmh', () {
    test('v_safe(0) is approximately 87 km/h, per ADR-003', () {
      expect(pregnolatoVSafeKmh(0), closeTo(86.9448, 1e-9));
    });

    test('decreases as depth increases, within the validated domain', () {
      final depths = [0.0, 50.0, 100.0, 150.0, 200.0, 250.0];
      final speeds = depths.map(pregnolatoVSafeKmh).toList();
      for (var i = 1; i < speeds.length; i++) {
        expect(speeds[i], lessThan(speeds[i - 1]));
      }
    });

    test('never goes negative, even past the domain where the raw quadratic '
        'would turn upward', () {
      expect(pregnolatoVSafeKmh(1000), greaterThanOrEqualTo(0));
      expect(pregnolatoVSafeKmh(1000), equals(pregnolatoVSafeKmh(300)));
    });

    test('rejects a negative depth', () {
      expect(() => pregnolatoVSafeKmh(-1), throwsA(isA<ArgumentError>()));
    });

    test('rejects a NaN depth -- regression for a 2026-09 security review '
        'finding: `NaN > domainMax` is false, so a NaN depth used to fall '
        'through to the quadratic unclamped, silently returning NaN', () {
      expect(
        () => pregnolatoVSafeKmh(double.nan),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('slowdownDelta', () {
    test('is exactly 1 when there is no depth observation', () {
      expect(slowdownDelta(freeFlowKmh: 30, depthMm: null), equals(1));
      expect(slowdownDelta(freeFlowKmh: 100, depthMm: null), equals(1));
    });

    test('the max(1, ...) clamp engages for an ordinary Chennai arterial '
        '(v_free ~= 30 km/h) even at shallow depth -- this is the ADR-003 '
        'invariant the whole cost function depends on', () {
      // v_safe(0) ~= 87 km/h > 30 km/h, so the raw ratio v_free/v_safe is
      // well below 1 here. Without max(1, ...) this would report a
      // *speed-up*, which is physically backwards for a hazard.
      final raw = 30 / pregnolatoVSafeKmh(0);
      expect(raw, lessThan(1));

      final delta = slowdownDelta(freeFlowKmh: 30, depthMm: 0);
      expect(delta, equals(1));
    });

    test('exceeds 1 once v_free is high enough that v_safe(h) is the '
        'binding constraint', () {
      // v_safe(150mm) is well under 87 km/h; a 100 km/h highway is slowed.
      final vSafe150 = pregnolatoVSafeKmh(150);
      final delta = slowdownDelta(freeFlowKmh: 100, depthMm: 150);
      expect(delta, closeTo(100 / vSafe150, 1e-9));
      expect(delta, greaterThan(1));
    });
  });
}
