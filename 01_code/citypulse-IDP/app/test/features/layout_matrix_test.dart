// Layout matrix: every screen at several phone, tablet and desktop sizes and at larger text, failing on any overflow or other layout
// exception. A traveller on a small or landscape phone, or with large text, must still be able to read and reach everything
// (the first-use disclaimer's button was once pushed off a short screen; this keeps that class of defect out).
import 'package:citypulse_app/src/features/map/route_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

const _sizes = <String, Size>{
  'small phone 320x568': Size(320, 568),
  'phone 360x640': Size(360, 640),
  'tall phone 412x915': Size(412, 915),
  'landscape phone 640x360': Size(640, 360),
  'tablet 768x1024': Size(768, 1024),
  'desktop 1280x800': Size(1280, 800),
};
const _scales = [1.0, 1.5, 2.0];

Future<void> _typeAndPick(WidgetTester tester, String field, String query) async {
  await tester.tap(find.byKey(Key('place-field-$field')));
  await tester.pump();
  await tester.enterText(find.byKey(Key('place-field-$field')), query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key('suggestion-$field-0')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('suggestion-$field-0')));
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in _sizes.entries) {
    for (final scale in _scales) {
      testWidgets('${entry.key} at ${scale}x text: map, a planned route, a question, help and settings', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // Name the widget behind any layout error (the framework's own handler still records it for takeException).
        final previous = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = RegExp(r'(lib/[^\s]+\.dart:\d+)').allMatches(d.toString()).map((m) => m.group(1)).toSet();
          debugPrint('LAYOUT ${d.exceptionAsString().split(String.fromCharCode(10)).first} @ $m');
          previous?.call(d);
        };
        addTearDown(() => FlutterError.onError = previous);
        final h = AppHarness();
        await h.pump(tester, size: entry.value);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'map screen');

        await _typeAndPick(tester, 'origin', 'usman');
        await _typeAndPick(tester, 'destination', 'velachery');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'planned route');
        expect(h.container.read(plannerProvider).status, PlanStatus.done);

        // the question box: reachable, usable, and its answer lays out
        final field = find.byKey(const Key('ask-field'));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'Give me the picture');
        await tester.tap(find.byKey(const Key('ask-send')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ask-answer')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'a question answered');

        for (final icon in [Icons.help_outline, Icons.settings_outlined]) {
          final tab = find.byIcon(icon);
          if (tab.evaluate().isEmpty) continue;
          await tester.tap(tab.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$icon screen');
        }
      });
    }
  }
}
