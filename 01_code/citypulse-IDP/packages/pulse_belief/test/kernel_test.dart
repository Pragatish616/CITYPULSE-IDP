import 'package:pulse_belief/pulse_belief.dart';
import 'package:test/test.dart';

void main() {
  group('SpatialKernel', () {
    test(
      'kappa(0) is 1.0 — an observation exactly on the edge gets full weight',
      () {
        final kernel = SpatialKernel();
        expect(kernel(0), equals(1.0));
      },
    );

    test('decays monotonically with distance', () {
      final kernel = SpatialKernel();
      final distances = [0.0, 10.0, 50.0, 100.0, 200.0];
      final weights = distances.map(kernel.call).toList();
      for (var i = 1; i < weights.length; i++) {
        expect(weights[i], lessThan(weights[i - 1]));
      }
    });

    test('is exactly zero beyond the cutoff', () {
      final kernel = SpatialKernel();
      expect(kernel(300.01), equals(0.0));
      expect(kernel(1000), equals(0.0));
    });

    test('is non-zero at exactly the cutoff', () {
      final kernel = SpatialKernel();
      expect(kernel(300), greaterThan(0.0));
    });

    test('rejects a negative distance', () {
      final kernel = SpatialKernel();
      expect(() => kernel(-1), throwsA(isA<ArgumentError>()));
    });

    test('rejects a NaN distance -- regression for a 2026-09 security review '
        'finding: `NaN > cutoffM` is false, so a NaN distance used to fall '
        'through to math.exp(-NaN/bandwidth), silently returning NaN instead '
        'of being screened out', () {
      final kernel = SpatialKernel();
      expect(() => kernel(double.nan), throwsA(isA<ArgumentError>()));
    });

    test('rejects a non-positive bandwidth or cutoff', () {
      expect(() => SpatialKernel(bandwidthM: 0), throwsA(isA<ArgumentError>()));
      expect(() => SpatialKernel(cutoffM: 0), throwsA(isA<ArgumentError>()));
    });
  });
}
