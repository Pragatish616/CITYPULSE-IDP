/// Routes and the responsive navigation shell.
///
/// Real URLs on the web (`/map`, `/help`, `/settings`) and deep links on
/// Android from one route table. A shareable plan is
/// `/map?from=13.0418,80.2341&to=12.9815,80.2180`.
library;

import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/features/help/help_screen.dart';
import 'package:citypulse_app/src/features/map/map_screen.dart';
import 'package:citypulse_app/src/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse_router/pulse_router.dart';

GeoPoint? _parsePoint(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0]);
  final lon = double.tryParse(parts[1]);
  if (lat == null || lon == null) return null;
  if (!lat.isFinite || !lon.isFinite) return null;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  return (lat: lat, lon: lon);
}

/// Builds the app's router.
GoRouter buildRouter() => GoRouter(
  initialLocation: '/map',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/map',
              builder: (context, state) => MapScreen(
                initialFrom: _parsePoint(state.uri.queryParameters['from']),
                initialTo: _parsePoint(state.uri.queryParameters['to']),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/help',
              builder: (context, state) => const HelpScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Bottom bar on phones, side rail on wide screens.
class AppShell extends ConsumerWidget {
  /// Creates the shell around the active branch.
  const AppShell({required this.shell, super.key});

  /// The navigation state.
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final items = [
      (Icons.map_outlined, Icons.map, s(Msg.navMap)),
      (Icons.help_outline, Icons.help, s(Msg.navHelp)),
      (Icons.settings_outlined, Icons.settings, s(Msg.navSettings)),
    ];
    void go(int i) =>
        shell.goBranch(i, initialLocation: i == shell.currentIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kWideBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  key: const Key('nav-rail'),
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: go,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final (icon, selected, label) in items)
                      NavigationRailDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selected),
                        label: Text(label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: shell),
              ],
            ),
          );
        }
        return Scaffold(
          body: shell,
          bottomNavigationBar: NavigationBar(
            key: const Key('nav-bar'),
            selectedIndex: shell.currentIndex,
            onDestinationSelected: go,
            destinations: [
              for (final (icon, selected, label) in items)
                NavigationDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selected),
                  label: label,
                ),
            ],
          ),
        );
      },
    );
  }
}
