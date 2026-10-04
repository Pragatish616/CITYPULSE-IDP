/// The main screen: the map, the planner, the result.
///
/// Compact widths (phones): the map fills the screen, the planner floats at the
/// top, the result is a draggable sheet. Wide widths (tablets, desktop
/// browsers): a 400 dp side panel holds the planner and result beside the map
/// (PLAN.md §4.1, Material window-size classes).
library;

import 'dart:async';
import 'dart:convert';

import 'package:citypulse_app/src/core/city.dart';
import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/core/theme.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/features/map/map_surface.dart';
import 'package:citypulse_app/src/features/map/place_field.dart';
import 'package:citypulse_app/src/features/map/route_card.dart';
import 'package:citypulse_app/src/features/map/route_controller.dart';
import 'package:citypulse_app/src/features/report/report_sheet.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:pulse_router/pulse_router.dart';

/// Width at which the layout switches to a side panel.
const double kWideBreakpoint = 840;

/// Watchlist candidates as GeoJSON points, from the bundled asset.
final watchlistGeoJsonProvider = FutureProvider<String>((ref) async {
  final raw = await ref
      .watch(assetBundleProvider)
      .loadString('assets/data/watchlist_candidates.json');
  final rows = (jsonDecode(raw) as List<Object?>).cast<Map<String, Object?>>();
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final r in rows)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [r['lon'], r['lat']],
          },
          'properties': {
            'id': r['id'],
            'category': r['category'],
            'verified': r['verified'],
          },
        },
    ],
  });
});

/// The map screen. [initialFrom] / [initialTo] come from a shared link.
class MapScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MapScreen({this.initialFrom, this.initialTo, super.key});

  /// Start from a link, if any.
  final GeoPoint? initialFrom;

  /// Destination from a link, if any.
  final GeoPoint? initialTo;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapHandle? _map;
  var _showFastest = false;

  /// Fraction of the screen height the draggable result sheet covers (phone
  /// layout), so the map buttons can ride above it instead of under it.
  var _sheetFraction = 0.0;

  @override
  void initState() {
    super.initState();
    final from = widget.initialFrom;
    final to = widget.initialTo;
    if (from != null || to != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final planner = ref.read(plannerProvider.notifier);
        if (from != null) planner.setOrigin(Place.dropped(from));
        if (to != null) planner.setDestination(Place.dropped(to));
      });
    }
  }

  GeoPoint get _centre =>
      _map?.cameraCenter() ?? cityCentre(ref.read(cityProvider));

  var _syncing = false;
  var _syncAgain = false;
  String? _appliedRisk;
  String? _appliedWatchlist;

  // --- Hazard overlay by visible area (ADR-020) -----------------------------------------------
  // Never fetched whole: the area in view plus a margin, only when the view leaves the area already
  // fetched, a quarter-second after the camera stops, hidden when zoomed too far out. Recent areas
  // are kept so panning back is instant.
  String? _riskText;
  GeoBounds? _riskRegion;
  String? _riskFor;
  int _riskSeq = 0;
  Timer? _riskDebounce;
  final _riskCache = <String, String>{};

  static const _riskPadding =
      0.5; // extra area on each side, as a fraction of the view
  static const _riskGrid =
      0.02; // degrees; regions snap outward to this so cache keys repeat
  static const _riskCacheSize = 8;

  static bool _covers(GeoBounds outer, GeoBounds inner) =>
      outer.minLat <= inner.minLat &&
      outer.minLon <= inner.minLon &&
      outer.maxLat >= inner.maxLat &&
      outer.maxLon >= inner.maxLon;

  static GeoBounds _padAndSnap(GeoBounds b) {
    final dLat = (b.maxLat - b.minLat) * _riskPadding;
    final dLon = (b.maxLon - b.minLon) * _riskPadding;
    double down(double v) => (v / _riskGrid).floorToDouble() * _riskGrid;
    double up(double v) => (v / _riskGrid).ceilToDouble() * _riskGrid;
    return (
      minLat: down(b.minLat - dLat),
      minLon: down(b.minLon - dLon),
      maxLat: up(b.maxLat + dLat),
      maxLon: up(b.maxLon + dLon),
    );
  }

  void _scheduleRisk({bool immediate = false}) {
    _riskDebounce?.cancel();
    _riskDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 250),
      () => unawaited(_refreshRisk()),
    );
  }

  void _setRisk(String? text) {
    if (identical(text, _riskText)) return;
    _riskText = text;
    unawaited(_syncMapState());
  }

  Future<void> _refreshRisk() async {
    final map = _map;
    if (map == null || !mounted) return;
    final settings = ref.read(settingsProvider);
    if (!settings.showHazard) {
      _setRisk(null);
      return;
    }
    final view = await map.view();
    if (view == null || !mounted) return;
    if (view.zoom < kRiskMinZoom) {
      _riskRegion = null;
      _setRisk(null);
      return;
    }
    final revision = ref.read(riskRevisionProvider);
    final stamp = '${settings.travel.wire}|$revision';
    final region = _riskRegion;
    if (_riskText != null &&
        _riskFor == stamp &&
        region != null &&
        _covers(region, view.bounds)) {
      return; // what is on the map already covers what is in view
    }
    final wanted = _padAndSnap(view.bounds);
    final key =
        '$stamp|${wanted.minLat}|${wanted.minLon}|${wanted.maxLat}|${wanted.maxLon}';
    final seq = ++_riskSeq;
    var text = _riskCache[key];
    if (text == null) {
      try {
        await ref.read(backendReadyProvider.future);
        text = await ref
            .read(routingBackendProvider)
            .riskGeoJson(travel: settings.travel, bounds: wanted);
        // A newer request started while this one was out: drop this answer.
        if (seq != _riskSeq || !mounted) return;
        _riskCache[key] = text;
        while (_riskCache.length > _riskCacheSize) {
          _riskCache.remove(_riskCache.keys.first);
        }
        // The overlay is a nicety: a failed fetch leaves the old one and the next move retries.
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        debugPrint('risk overlay fetch failed: $e');
        return;
      }
    }
    _riskRegion = wanted;
    _riskFor = stamp;
    _setRisk(text);
  }

  @override
  void dispose() {
    _riskDebounce?.cancel();
    super.dispose();
  }

  /// Pushes the current state to the map. Calls overlap (every planner,
  /// settings and data change triggers one), and each pass awaits several
  /// platform calls, so an earlier pass could finish after a later one and
  /// paint stale data -- a route would vanish seconds after it was drawn.
  /// This runs at most one pass at a time; a request that arrives mid-pass
  /// schedules exactly one more pass, which reads the *latest* state.
  Future<void> _syncMapState() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _applyMapState();
      } while (_syncAgain);
      // A failing map call must not take the screen down; the next state
      // change retries.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      debugPrint('map sync failed: $e');
      debugPrint('$st');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _applyMapState() async {
    final map = _map;
    if (map == null) return;
    final settings = ref.read(settingsProvider);
    final planner = ref.read(plannerProvider);

    // The risk layer can be large; only re-send it when it, or whether it is
    // shown, actually changed.
    final risk = settings.showHazard ? _riskText : null;
    if (!identical(risk, _appliedRisk)) {
      _appliedRisk = risk;
      await map.setRisk(risk);
    }
    final watch = settings.showWatchlist
        ? ref.read(watchlistGeoJsonProvider).value
        : null;
    if (!identical(watch, _appliedWatchlist)) {
      _appliedWatchlist = watch;
      await map.setWatchlist(watch);
    }

    final view = planner.route;
    await map.setRoute(
      path: view?.path,
      fastest: _showFastest && (view?.detours ?? false)
          ? view?.fastestPath
          : null,
      markers: [
        if (planner.origin != null)
          MapMarker(MarkerKind.origin, planner.origin!.point),
        if (planner.destination != null)
          MapMarker(MarkerKind.destination, planner.destination!.point),
        if (view != null)
          for (final p in view.avoidedHazards) MapMarker(MarkerKind.avoided, p),
      ],
    );
  }

  Future<void> _showTapSheet(GeoPoint point) async {
    final s = ref.read(stringsProvider);
    final planner = ref.read(plannerProvider.notifier);
    final place = Place.dropped(point);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              title: Text(
                '${point.lat.toStringAsFixed(5)}, ${point.lon.toStringAsFixed(5)}',
              ),
            ),
            ListTile(
              key: const Key('tap-set-start'),
              leading: const Icon(Icons.trip_origin),
              title: Text(s(Msg.setStart)),
              onTap: () {
                Navigator.pop(sheetContext);
                planner.setOrigin(place);
              },
            ),
            ListTile(
              key: const Key('tap-set-destination'),
              leading: const Icon(Icons.place),
              title: Text(s(Msg.setDestination)),
              onTap: () {
                Navigator.pop(sheetContext);
                planner.setDestination(place);
              },
            ),
            ListTile(
              key: const Key('tap-report'),
              leading: const Icon(Icons.water_drop_outlined),
              title: Text(s(Msg.reportHere)),
              onTap: () {
                Navigator.pop(sheetContext);
                showReportSheet(context, point);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the map in step with state. These fire whenever the inputs change.
    ref
      ..listen(plannerProvider, (prev, next) {
        _syncMapState();
        final route = next.route;
        if (route != null && route != prev?.route) {
          _showFastest = false;
          _map?.fit([...route.path, ...route.avoidedHazards]);
        }
      })
      ..listen(riskRevisionProvider, (_, _) => _scheduleRisk(immediate: true))
      ..listen(watchlistGeoJsonProvider, (_, _) => _syncMapState())
      ..listen(settingsProvider, (_, _) {
        _syncMapState();
        _scheduleRisk(immediate: true);
      });

    final callbacks = MapSurfaceCallbacks(
      onReady: (handle) {
        _map = handle;
        _syncMapState();
        _scheduleRisk(immediate: true);
      },
      onCameraIdle: _scheduleRisk,
      onTap: _showTapSheet,
      onLongPress: _showTapSheet,
    );
    final mapWidget = Stack(
      children: [
        Positioned.fill(
          child: ref.watch(mapSurfaceBuilderProvider)(context, callbacks),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: PointerInterceptor(child: const _AttributionChip()),
        ),
      ],
    );
    Widget buttons() => PointerInterceptor(
      child: _MapButtons(
        onReport: () => showReportSheet(context, _centre),
        onLayers: () => _showLayers(context),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kWideBreakpoint;
        if (wide) {
          return Row(
            children: [
              SizedBox(
                width: 400,
                child: Material(
                  elevation: 1,
                  child: SafeArea(
                    child: _PlannerPanel(
                      centre: () => _centre,
                      showFastest: _showFastest,
                      onToggleFastest: _toggleFastest,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: mapWidget),
                    Positioned(right: 8, bottom: 24, child: buttons()),
                  ],
                ),
              ),
            ],
          );
        }
        final height = constraints.maxHeight;
        final hasResult =
            ref.watch(plannerProvider.select((p) => p.status)) !=
            PlanStatus.idle;
        // Sit just above the sheet, but never higher than mid-screen.
        // Until the sheet reports its extent it is at its initial 42%.
        final fraction = _sheetFraction == 0 ? 0.42 : _sheetFraction;
        final lift = hasResult
            ? (fraction * height).clamp(0.0, height * 0.55)
            : 0.0;
        return Stack(
          children: [
            Positioned.fill(child: mapWidget),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: PointerInterceptor(
                    child: _CompactPlanner(centre: () => _centre),
                  ),
                ),
              ),
            ),
            Positioned(right: 8, bottom: 24 + lift, child: buttons()),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (n) {
                if ((n.extent - _sheetFraction).abs() > 0.005) {
                  setState(() => _sheetFraction = n.extent);
                }
                return false;
              },
              child: _ResultSheet(
                showFastest: _showFastest,
                onToggleFastest: _toggleFastest,
              ),
            ),
          ],
        );
      },
    );
  }

  void _toggleFastest() {
    setState(() => _showFastest = !_showFastest);
    _syncMapState();
  }

  void _showLayers(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _LayersSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// Planner
// ---------------------------------------------------------------------------

class _TravelSelector extends ConsumerWidget {
  const _TravelSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final travel = ref.watch(settingsProvider.select((x) => x.travel));
    // Four modes do not fit with text labels on a narrow phone; below this width show the icons and
    // keep the names as tooltips (and as the accessible label).
    return LayoutBuilder(
      builder: (context, box) {
        final showText = box.maxWidth >= 480;
        ButtonSegment<TravelType> segment(
          TravelType type,
          IconData icon,
          Msg name,
        ) => ButtonSegment(
          value: type,
          icon: Icon(icon),
          tooltip: s(name),
          label: showText
              ? Text(s(name), overflow: TextOverflow.ellipsis)
              : null,
        );
        return SegmentedButton<TravelType>(
          key: const Key('travel-selector'),
          showSelectedIcon: false,
          segments: [
            segment(
              TravelType.commuter,
              Icons.directions_car_outlined,
              Msg.commuter,
            ),
            segment(TravelType.cyclist, Icons.directions_bike, Msg.cyclist),
            segment(
              TravelType.pedestrian,
              Icons.directions_walk,
              Msg.pedestrian,
            ),
            segment(
              TravelType.emergency,
              Icons.emergency_outlined,
              Msg.emergency,
            ),
          ],
          selected: {travel},
          onSelectionChanged: (v) =>
              ref.read(settingsProvider.notifier).setTravel(v.first),
        );
      },
    );
  }
}

class _PlannerFields extends ConsumerWidget {
  const _PlannerFields({required this.centre});

  final GeoPoint Function() centre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final planner = ref.watch(plannerProvider);
    final notifier = ref.read(plannerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlaceField(
          fieldKey: 'origin',
          label: s(Msg.whereFrom),
          place: planner.origin,
          near: centre,
          onSelected: notifier.setOrigin,
          onUseMapCentre: () => notifier.setOrigin(Place.dropped(centre())),
        ),
        const SizedBox(height: 8),
        PlaceField(
          fieldKey: 'destination',
          label: s(Msg.whereTo),
          place: planner.destination,
          near: centre,
          onSelected: notifier.setDestination,
          onUseMapCentre: () =>
              notifier.setDestination(Place.dropped(centre())),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _TravelSelectorScaled()),
            IconButton(
              key: const Key('swap'),
              tooltip: s(Msg.swap),
              onPressed: planner.ready ? notifier.swap : null,
              icon: const Icon(Icons.swap_vert),
            ),
            IconButton(
              key: const Key('clear'),
              tooltip: s(Msg.clear),
              onPressed: planner.origin != null || planner.destination != null
                  ? notifier.clear
                  : null,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ],
    );
  }
}

class _TravelSelectorScaled extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: _TravelSelector(),
  );
}

class _CompactPlanner extends ConsumerWidget {
  const _CompactPlanner({required this.centre});

  final GeoPoint Function() centre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _EventBanner(),
              _PlannerFields(centre: centre),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlannerPanel extends ConsumerWidget {
  const _PlannerPanel({
    required this.centre,
    required this.showFastest,
    required this.onToggleFastest,
  });

  final GeoPoint Function() centre;
  final bool showFastest;
  final VoidCallback onToggleFastest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _EventBanner(),
        _PlannerFields(centre: centre),
        const SizedBox(height: 16),
        _PlanOutcome(
          showFastest: showFastest,
          onToggleFastest: onToggleFastest,
        ),
      ],
    );
  }
}

/// Loading, error or the route card, depending on the planner state.
class _PlanOutcome extends ConsumerWidget {
  const _PlanOutcome({
    required this.showFastest,
    required this.onToggleFastest,
  });

  final bool showFastest;
  final VoidCallback onToggleFastest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final planner = ref.watch(plannerProvider);
    switch (planner.status) {
      case PlanStatus.idle:
        return const SizedBox.shrink();
      case PlanStatus.loading:
        return Padding(
          key: const Key('planning'),
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(s(Msg.planning)),
            ],
          ),
        );
      case PlanStatus.failed:
        return Card(
          key: const Key('plan-error'),
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_failureText(s, planner.failure!)),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('retry'),
                  onPressed: ref.read(plannerProvider.notifier).plan,
                  child: Text(s(Msg.tryAgain)),
                ),
              ],
            ),
          ),
        );
      case PlanStatus.done:
        return RouteCard(
          view: planner.route!,
          showFastest: showFastest,
          onToggleFastest: onToggleFastest,
        );
    }
  }

  static String _failureText(Strings s, RoutingFailure f) => switch (f) {
    RoutingFailure.originOutside => s(Msg.errorOriginOutside),
    RoutingFailure.destinationOutside => s(Msg.errorDestinationOutside),
    RoutingFailure.sameLocation => s(Msg.errorSameLocation),
    RoutingFailure.noRoute => s(Msg.errorNoRoute),
    RoutingFailure.network => s(Msg.errorNetwork),
    RoutingFailure.server => s(Msg.errorServer),
    RoutingFailure.notReady => s(Msg.errorNotReady),
  };
}

class _ResultSheet extends ConsumerWidget {
  const _ResultSheet({
    required this.showFastest,
    required this.onToggleFastest,
  });

  final bool showFastest;
  final VoidCallback onToggleFastest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(plannerProvider.select((p) => p.status));
    if (status == PlanStatus.idle) return const SizedBox.shrink();
    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.14,
      maxChildSize: 0.9,
      builder: (context, controller) => PointerInterceptor(
        child: Material(
          elevation: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            key: const Key('result-sheet'),
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _PlanOutcome(
                showFastest: showFastest,
                onToggleFastest: onToggleFastest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlays
// ---------------------------------------------------------------------------

/// States the flood-event mode, so a traveller can see why the hazard map is
/// or is not shaping routes (F-09). Shown in plain words, never as "all clear".
class _EventBanner extends ConsumerWidget {
  const _EventBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A region with no flood-hazard layer has nothing to switch on or off: saying "the hazard map is
    // applied" there would be false (ADR-020). A region with a detailed city inside it (Chennai in
    // Tamil Nadu, ADR-022) says which city the flood map covers.
    final city = ref.watch(cityProvider);
    final detail = ref.watch(detailCitiesProvider).where((c) => c.hazardLayer);
    if (!city.hazardLayer && detail.isEmpty) return const SizedBox.shrink();
    final scope = city.hazardLayer
        ? ''
        : '${detail.first.name.forLanguage(ref.watch(stringsProvider).language == AppLanguage.ta ? 'ta' : 'en')} · ';
    final state = ref.watch(eventStateProvider).value;
    if (state == null) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final scheme = Theme.of(context).colorScheme;
    final (text, colour, icon) = switch (state) {
      EventState.dry => (
        s(Msg.eventDry),
        scheme.surfaceContainerHighest,
        Icons.info_outline,
      ),
      EventState.watch => (
        s(Msg.eventWatch),
        scheme.tertiaryContainer,
        Icons.visibility_outlined,
      ),
      EventState.active => (
        s(Msg.eventActive),
        scheme.errorContainer,
        Icons.water_outlined,
      ),
    };
    return Container(
      key: Key('event-banner-${state.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$scope$text',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttributionChip extends ConsumerWidget {
  const _AttributionChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          s(Msg.mapAttribution),
          style: const TextStyle(fontSize: 10, color: Colors.black87),
        ),
      ),
    );
  }
}

class _MapButtons extends ConsumerWidget {
  const _MapButtons({required this.onReport, required this.onLayers});

  final VoidCallback onReport;
  final VoidCallback onLayers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          key: const Key('layers-button'),
          heroTag: 'layers',
          tooltip: s(Msg.layers),
          onPressed: onLayers,
          child: const Icon(Icons.layers_outlined),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          key: const Key('report-button'),
          heroTag: 'report',
          onPressed: onReport,
          icon: const Icon(Icons.water_drop_outlined),
          label: Text(s(Msg.reportHere)),
        ),
      ],
    );
  }
}

class _LayersSheet extends ConsumerWidget {
  const _LayersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s(Msg.layers), style: text.titleLarge),
            SwitchListTile(
              key: const Key('switch-hazard'),
              contentPadding: EdgeInsets.zero,
              title: Text(s(Msg.hazardMap)),
              subtitle: Text(s(Msg.hazardMapNote)),
              value: settings.showHazard,
              onChanged: (v) => notifier.setShowHazard(value: v),
            ),
            SwitchListTile(
              key: const Key('switch-watchlist'),
              contentPadding: EdgeInsets.zero,
              title: Text(s(Msg.watchlist)),
              subtitle: Text(s(Msg.watchlistNote)),
              value: settings.showWatchlist,
              onChanged: (v) => notifier.setShowWatchlist(value: v),
            ),
            const Divider(),
            Text(s(Msg.legend), style: text.titleSmall),
            const SizedBox(height: 8),
            const _LegendRow(
              swatch: _Swatch(
                colours: [
                  RiskPalette.lowColor,
                  RiskPalette.midColor,
                  RiskPalette.highColor,
                  RiskPalette.severeColor,
                ],
                dashed: true,
              ),
              messageKey: Msg.legendMapOnly,
            ),
            const _LegendRow(
              swatch: _Swatch(
                colours: [
                  RiskPalette.lowColor,
                  RiskPalette.midColor,
                  RiskPalette.highColor,
                  RiskPalette.severeColor,
                ],
                dashed: false,
              ),
              messageKey: Msg.legendReported,
            ),
            const _LegendRow(
              swatch: _Dot(RiskPalette.avoidedColor),
              messageKey: Msg.legendAvoided,
            ),
            const _LegendRow(
              swatch: _Dot(RiskPalette.watchlistColor),
              messageKey: Msg.watchlist,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends ConsumerWidget {
  const _LegendRow({required this.swatch, required this.messageKey});

  final Widget swatch;
  final Msg messageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 64, child: swatch),
          const SizedBox(width: 12),
          Expanded(child: Text(s(messageKey))),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.colour);

  final Color colour;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colours, required this.dashed});

  final List<Color> colours;
  final bool dashed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 8,
    child: Row(
      children: [
        for (final c in colours)
          Expanded(
            child: dashed
                ? Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        Expanded(
                          child: ColoredBox(
                            color: c,
                            child: const SizedBox(height: 4),
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                    ],
                  )
                : ColoredBox(color: c, child: const SizedBox(height: 6)),
          ),
      ],
    ),
  );
}
