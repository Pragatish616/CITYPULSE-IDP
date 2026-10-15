// ADR-032: what "Avoid reported accidents" did on a trip, read from the trace's own facts.
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/features/map/route_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_router/pulse_router.dart';

import '../helpers/harness.dart';

ContextFact _f(String key, Object value) =>
    ContextFact(key: key, value: value, label: key, asOf: DateTime.utc(2026, 10, 15));

DecisionTrace _with(List<ContextFact> facts) {
  final t = sampleTrace();
  return DecisionTrace(
    queryId: t.queryId,
    computedAt: t.computedAt,
    mode: t.mode,
    userClass: t.userClass,
    z: t.z,
    lambda: t.lambda,
    chosen: t.chosen,
    alternatives: t.alternatives,
    contextFacts: facts,
    dataGaps: t.dataGaps,
    confidenceBand: t.confidenceBand,
  );
}

void main() {
  final s = Strings(AppLanguage.en);

  test('nothing to avoid: says so, and that the route is unchanged', () {
    expect(accidentStatusText(_with(const []), s), contains('no accident reports in the data right now'));
  });

  test('reports kept off: gives the number', () {
    expect(accidentStatusText(_with([_f('restricted_segments', 3)]), s), contains('keeping off 3 reported or closed road segments'));
  });

  test('no route can keep off every report: says the usual route is shown', () {
    expect(
      accidentStatusText(_with([_f('restricted_segments', 2), _f('limits_not_met', true)]), s),
      contains('the usual route is shown'),
    );
  });

  test('Tamil text exists for all three', () {
    final ta = Strings(AppLanguage.ta);
    for (final t in [_with(const []), _with([_f('restricted_segments', 1)]), _with([_f('limits_not_met', true)])]) {
      expect(accidentStatusText(t, ta), contains('விபத்துகளைத் தவிர்க்கிறது'));
    }
  });
}
