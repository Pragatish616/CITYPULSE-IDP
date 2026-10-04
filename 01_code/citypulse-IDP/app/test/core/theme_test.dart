// The app uses orange, not red, for warnings, errors and the hazard overlay.
import 'package:citypulse_app/src/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _hue(Color c) => HSLColor.fromColor(c).hue;

// Red sits within about 10 degrees of 0 (or 360); orange is roughly 15 to 45.
void _isOrange(Color c, String what) {
  final h = _hue(c);
  expect(h, inInclusiveRange(15, 45), reason: '$what has hue $h, not orange');
}

void main() {
  for (final brightness in Brightness.values) {
    test('the ${brightness.name} theme\'s error colours are orange', () {
      final scheme = buildTheme(brightness).colorScheme;
      _isOrange(scheme.error, 'error');
      _isOrange(scheme.errorContainer, 'errorContainer');
      _isOrange(scheme.onErrorContainer, 'onErrorContainer');
    });
  }

  test('the hazard overlay is a light orange throughout: never red, never brown', () {
    for (final c in [RiskPalette.lowColor, RiskPalette.midColor, RiskPalette.highColor, RiskPalette.severeColor]) {
      // Light: brown and maroon have low lightness.
      expect(HSLColor.fromColor(c).lightness, greaterThan(0.55), reason: '$c is too dark');
    }
    _isOrange(RiskPalette.midColor, 'mid');
    _isOrange(RiskPalette.highColor, 'high');
    _isOrange(RiskPalette.severeColor, 'severe');
    // Darker as the risk rises, so the order reads without relying on hue alone.
    double lightness(Color c) => HSLColor.fromColor(c).lightness;
    expect(lightness(RiskPalette.lowColor), greaterThan(lightness(RiskPalette.midColor)));
    expect(lightness(RiskPalette.midColor), greaterThan(lightness(RiskPalette.highColor)));
    expect(lightness(RiskPalette.highColor), greaterThan(lightness(RiskPalette.severeColor)));
  });

  test('the string and Color forms of the palette agree', () {
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    expect(hex(RiskPalette.highColor), RiskPalette.riskHigh);
    expect(hex(RiskPalette.severeColor), RiskPalette.riskSevere);
    expect(hex(RiskPalette.midColor), RiskPalette.riskMid);
    expect(hex(RiskPalette.lowColor), RiskPalette.riskLow);
    expect(hex(RiskPalette.avoidedColor), RiskPalette.avoided);
  });
}
