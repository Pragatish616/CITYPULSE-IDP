// Verifies ADR-011's gate behaviour: the disclaimer shows on first launch
// and the gated screen is not reachable until it's acknowledged, and that
// acknowledging it persists per app version (a version bump re-shows it).

import 'package:citypulse_app/src/disclaimer/disclaimer_gate.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_store.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(DisclaimerStore store, {String appVersion = '0.1.0'}) {
  return MaterialApp(
    home: DisclaimerGate(
      appVersion: appVersion,
      store: store,
      child: const Scaffold(
        body: Center(key: Key('gated-screen'), child: Text('route screen')),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'shows the verbatim ADR-011 disclaimer on first launch and blocks the '
    'gated screen',
    (tester) async {
      final store = InMemoryDisclaimerStore();
      await tester.pumpWidget(_wrap(store));
      await tester.pumpAndSettle();

      expect(find.text(kFirstUseDisclaimer), findsOneWidget);
      expect(find.byKey(const Key('gated-screen')), findsNothing);
    },
  );

  testWidgets('acknowledging the disclaimer lifts the gate', (tester) async {
    final store = InMemoryDisclaimerStore();
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('first-use-disclaimer-accept')));
    await tester.pumpAndSettle();

    expect(find.text(kFirstUseDisclaimer), findsNothing);
    expect(find.byKey(const Key('gated-screen')), findsOneWidget);
    expect(await store.isAcknowledged('0.1.0'), isTrue);
  });

  testWidgets('a version already acknowledged does not show the gate again', (
    tester,
  ) async {
    final store = InMemoryDisclaimerStore(acknowledgedVersions: {'0.1.0'});
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    expect(find.text(kFirstUseDisclaimer), findsNothing);
    expect(find.byKey(const Key('gated-screen')), findsOneWidget);
  });

  testWidgets(
    'a new app version re-shows the disclaimer even if an older version was '
    'acknowledged (ADR-011: "once per app version")',
    (tester) async {
      final store = InMemoryDisclaimerStore(acknowledgedVersions: {'0.1.0'});
      await tester.pumpWidget(_wrap(store, appVersion: '0.2.0'));
      await tester.pumpAndSettle();

      expect(find.text(kFirstUseDisclaimer), findsOneWidget);
      expect(find.byKey(const Key('gated-screen')), findsNothing);
    },
  );
}
