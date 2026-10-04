import 'package:citypulse_app/src/core/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every message key has text in both languages', () {
    for (final key in Msg.values) {
      expect(englishStrings[key], isNotNull, reason: 'en missing $key');
      expect(tamilStrings[key], isNotNull, reason: 'ta missing $key');
      expect(englishStrings[key]!.trim(), isNotEmpty, reason: 'en empty $key');
      expect(tamilStrings[key]!.trim(), isNotEmpty, reason: 'ta empty $key');
    }
    expect(englishStrings.length, Msg.values.length);
    expect(tamilStrings.length, Msg.values.length);
  });

  test('placeholders survive translation', () {
    for (final strings in [englishStrings, tamilStrings]) {
      expect(strings[Msg.longerThanFastest], contains('{n}'));
    }
    const en = Strings(AppLanguage.en);
    const ta = Strings(AppLanguage.ta);
    expect(
      en.withNumber(Msg.longerThanFastest, 4),
      '4 min longer than the fastest route',
    );
    expect(ta.withNumber(Msg.longerThanFastest, 4), contains('4'));
    expect(ta.withNumber(Msg.longerThanFastest, 4), isNot(contains('{n}')));
  });

  test('ADR-011: no UI string tells the traveller a road is safe, dry, '
      'clear, open or fine, or says "go ahead"', () {
    // The report form's own option ("The water has cleared") and the generic
    // "Clear" button are the traveller's words / a verb, not claims by the app.
    const exempt = {Msg.reportCleared, Msg.clear};
    final banned = RegExp(
      r'\b(safe|safely|safest|dry|clear|cleared|open|passable|fine|ok|okay)\b|'
      r'go ahead|all clear|good to go|no risk|risk-free',
      caseSensitive: false,
    );
    for (final key in Msg.values) {
      if (exempt.contains(key)) continue;
      // "Open Database Licence" is the licence's legal name (ODbL), not a claim
      // about a road; every other word of the text is still checked.
      final text = englishStrings[key]!.replaceAll('Open Database Licence', 'ODbL');
      expect(banned.hasMatch(text), isFalse, reason: '$key: "$text"');
    }
  });

  test('ADR-011: the Tamil text avoids the verifier\'s safety stems too', () {
    const exempt = {Msg.reportCleared, Msg.clear};
    const stems = [
      'பாதுகாப்',
      'வறண்',
      'காய்ந்',
      'செல்லலாம்',
      'போகலாம்',
      'கடக்கலாம்',
      'தொடரலாம்',
      'திறந்',
      'தெளிவாக',
    ];
    for (final key in Msg.values) {
      if (exempt.contains(key)) continue;
      final text = tamilStrings[key]!;
      for (final stem in stems) {
        expect(text.contains(stem), isFalse, reason: '$key contains $stem');
      }
    }
  });

  test('helpers format minutes and kilometres in both languages', () {
    const en = Strings(AppLanguage.en);
    const ta = Strings(AppLanguage.ta);
    expect(en.minutes(12), '12 min');
    expect(ta.minutes(12), '12 நிமி');
    // From 90 minutes up the time is given in hours (a walk is easily two hours).
    expect(en.minutes(89), '89 min');
    expect(en.minutes(130), '2 h 10 min');
    expect(en.minutes(120), '2 h');
    expect(ta.minutes(130), '2 மணி 10 நிமி');
    expect(en.kilometres(9320), '9.3 km');
    expect(ta.kilometres(9320), '9.3 கி.மீ');
  });

  test('unknown language codes fall back to English', () {
    expect(AppLanguage.fromCode(null), AppLanguage.en);
    expect(AppLanguage.fromCode('fr'), AppLanguage.en);
    expect(AppLanguage.fromCode('ta'), AppLanguage.ta);
  });
}
