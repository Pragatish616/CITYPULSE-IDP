// ADR-018: the texts that used to say "Chennai" now follow the city.
import 'package:citypulse_app/src/core/strings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  final chennai = testCity();
  final testville = noHazardCity();

  test('for Chennai the texts are exactly what they were before the refactor',
      () {
    const en = AppLanguage.en;
    final s = Strings(en, city: chennai);
    expect(
      s(Msg.errorOriginOutside),
      'The start point is outside the mapped Chennai road network.',
    );
    expect(s(Msg.loadingMap), 'Loading the Chennai road network…');
    expect(s(Msg.hazardMapNote), contains('2015 Greater Chennai Corporation'));
    expect(s(Msg.helpAboutDataBody), contains('flood-hazard zones from 2015'));
    expect(s(Msg.dataSourcesBody), contains('published on OpenCity (public domain)'));
  });

  test('for another city the name and the honest no-hazard-layer texts appear',
      () {
    final s = Strings(AppLanguage.en, city: testville);
    expect(s(Msg.errorOriginOutside), contains('Testville'));
    expect(s(Msg.errorOriginOutside), isNot(contains('Chennai')));
    expect(s(Msg.loadingMap), 'Loading the Testville road network…');
    expect(s(Msg.hazardMapNote), contains('No flood-hazard layer'));
    expect(s(Msg.helpAboutDataBody), contains('No flood-hazard layer'));
    expect(s(Msg.dataSourcesBody), isNot(contains('Chennai')));
    final ta = Strings(AppLanguage.ta, city: testville);
    expect(ta(Msg.errorDestinationOutside), contains('டெஸ்ட்வில்'));
  });

  test('no placeholder survives in any string, either language, either city',
      () {
    for (final city in [chennai, testville]) {
      for (final lang in AppLanguage.values) {
        final s = Strings(lang, city: city);
        for (final key in Msg.values) {
          expect(
            s(key),
            isNot(matches(RegExp(r'\{(city|hazard_note|about_data|data_credit)\}'))),
            reason: '${city.id} ${lang.name} $key',
          );
        }
      }
    }
  });

  test('no string names Chennai unless it comes from the Chennai config', () {
    final s = Strings(AppLanguage.en, city: testville);
    for (final key in Msg.values) {
      expect(s(key), isNot(contains('Chennai')), reason: '$key');
    }
    final ta = Strings(AppLanguage.ta, city: testville);
    for (final key in Msg.values) {
      expect(ta(key), isNot(contains('சென்னை')), reason: '$key');
    }
  });

  test('ADR-011 holds for the resolved texts too, including the ones that '
      'come from the city config', () {
    final banned = RegExp(
      r'(safe|safely|safest|dry|clear|cleared|open|passable|fine|ok|okay)|'
      r'go ahead|all clear|good to go|no risk|risk-free',
      caseSensitive: false,
    );
    const exempt = {Msg.reportCleared, Msg.clear};
    for (final city in [chennai, testville]) {
      final s = Strings(AppLanguage.en, city: city);
      for (final key in Msg.values) {
        if (exempt.contains(key)) continue;
        final text = s(key).replaceAll('Open Database Licence', 'ODbL');
        expect(banned.hasMatch(text), isFalse, reason: '${city.id} $key: "$text"');
      }
    }
  });
}
