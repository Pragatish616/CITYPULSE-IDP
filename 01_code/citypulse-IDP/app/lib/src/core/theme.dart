/// Material 3 theme and the risk palette.
///
/// The palette follows ADR-011 and PLAN.md §6.1: **no green anywhere that could
/// read as "all clear"**, and colour is never the only signal -- the map also
/// encodes evidence with line style (dashed = hazard map only, solid = a report
/// exists) and width, so a colour-blind traveller can read it.
library;

import 'package:flutter/material.dart';

/// Brand seed colour.
const Color kSeedColor = Color(0xFF1F5FA8);

/// Colours for the map overlay and route lines, as CSS-style hex strings
/// (MapLibre takes strings) with the matching [Color] for Flutter widgets.
class RiskPalette {
  const RiskPalette._();

  /// Chosen route.
  static const String route = '#1F5FA8';

  /// Casing drawn under the chosen route so it reads on any basemap.
  static const String routeCasing = '#FFFFFF';

  /// Fastest route when it differs from the chosen one.
  static const String fastest = '#6B7280';

  /// Hazard edges at p ~ 0.25 (hazard map "High").
  static const String riskLow = '#FCE1B0';

  /// Mid risk.
  static const String riskMid = '#F9C47C';

  /// High risk.
  static const String riskHigh = '#F6A862';

  /// Highest risk.
  static const String riskSevere = '#F2914A';

  /// Origin marker.
  static const String origin = '#1F5FA8';

  /// Destination marker.
  static const String destination = '#1B1B1B';

  /// Marker for a hazard the chosen route avoids.
  static const String avoided = '#D4561A';

  /// Watchlist candidate pin.
  static const String watchlist = '#7B3FA0';

  /// Flutter colours for legends (must match the strings above).
  static const Color lowColor = Color(0xFFFCE1B0);
  static const Color midColor = Color(0xFFF9C47C);
  static const Color highColor = Color(0xFFF6A862);
  static const Color severeColor = Color(0xFFF2914A);
  static const Color watchlistColor = Color(0xFF7B3FA0);

  /// The marker for a hazard the chosen route avoids: a stronger orange than the overlay so a single
  /// point stands out. Must match [avoided].
  static const Color avoidedColor = Color(0xFFD4561A);
}

/// Builds the app theme for [brightness].
ThemeData buildTheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: kSeedColor,
    brightness: brightness,
  );
  // No red anywhere: the theme's "error" family (the flood banner, the emergency box on the Help screen,
  // failed-route cards) is a soft orange. Text on each container keeps at least 4.5:1 contrast.
  final dark = brightness == Brightness.dark;
  final scheme = base.copyWith(
    error: dark ? const Color(0xFFFFB68A) : const Color(0xFFB8470F),
    errorContainer: dark ? const Color(0xFF5A3314) : const Color(0xFFFFE1C8),
    onErrorContainer: dark ? const Color(0xFFFFDCC0) : const Color(0xFF5C2D00),
  );
  return ThemeData(
    useMaterial3: true,
    // Bundled subset fonts (assets/fonts): no font request to a third party.
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['NotoSansTamil'],
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    // 48 dp minimum touch targets (PLAN.md §6.1).
    materialTapTargetSize: MaterialTapTargetSize.padded,
    cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}
