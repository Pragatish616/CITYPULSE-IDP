/// State of the route planner: start, destination, and the latest result.
library;

import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the planner is.
enum PlanStatus {
  /// Nothing to compute yet.
  idle,

  /// A request is in flight.
  loading,

  /// [PlannerState.route] is set.
  done,

  /// [PlannerState.failure] is set.
  failed,
}

/// Immutable planner state.
class PlannerState {
  /// Creates a state.
  const PlannerState({
    this.origin,
    this.destination,
    this.status = PlanStatus.idle,
    this.route,
    this.failure,
  });

  /// Chosen start.
  final Place? origin;

  /// Chosen destination.
  final Place? destination;

  /// Where the request stands.
  final PlanStatus status;

  /// The latest route.
  final RouteView? route;

  /// Why the latest request failed.
  final RoutingFailure? failure;

  /// Whether both ends are chosen.
  bool get ready => origin != null && destination != null;

  /// A copy with replaced fields; pass [clearResult] to drop route/failure.
  PlannerState copyWith({
    Place? origin,
    Place? destination,
    bool clearOrigin = false,
    bool clearDestination = false,
    PlanStatus? status,
    RouteView? route,
    RoutingFailure? failure,
    bool clearResult = false,
  }) => PlannerState(
    origin: clearOrigin ? null : (origin ?? this.origin),
    destination: clearDestination ? null : (destination ?? this.destination),
    status: status ?? this.status,
    route: clearResult ? null : (route ?? this.route),
    failure: clearResult ? null : (failure ?? this.failure),
  );
}

/// Owns [PlannerState] and runs requests.
class PlannerNotifier extends Notifier<PlannerState> {
  var _generation = 0;

  @override
  PlannerState build() {
    // A different travel type changes z and λ, so re-plan.
    ref.listen(settingsProvider.select((s) => s.travel), (_, _) {
      if (state.ready) plan();
    });
    return const PlannerState();
  }

  /// Sets the start (and plans if the destination is already set).
  void setOrigin(Place place) {
    state = state.copyWith(
      origin: place,
      clearResult: true,
      status: PlanStatus.idle,
    );
    if (state.ready) plan();
  }

  /// Sets the destination (and plans if the start is already set).
  void setDestination(Place place) {
    state = state.copyWith(
      destination: place,
      clearResult: true,
      status: PlanStatus.idle,
    );
    if (state.ready) plan();
  }

  /// Swaps start and destination.
  void swap() {
    final o = state.origin;
    final d = state.destination;
    state = PlannerState(origin: d, destination: o);
    if (state.ready) plan();
  }

  /// Forgets everything.
  void clear() {
    _generation++;
    state = const PlannerState();
  }

  /// Computes the route for the current ends and travel type. A newer request
  /// supersedes an older one, so a slow answer never overwrites a fresh one.
  Future<void> plan() async {
    final origin = state.origin;
    final destination = state.destination;
    if (origin == null || destination == null) return;
    final mine = ++_generation;
    state = state.copyWith(status: PlanStatus.loading, clearResult: true);
    final travel = ref.read(settingsProvider).travel;
    try {
      final backend = ref.read(routingBackendProvider);
      await backend.warmUp();
      final view = await backend.route(
        from: origin.point,
        to: destination.point,
        travel: travel,
        at: ref.read(clockProvider)(),
      );
      if (mine != _generation) return;
      state = state.copyWith(status: PlanStatus.done, route: view);
    } on RoutingException catch (e) {
      if (mine != _generation) return;
      state = state.copyWith(status: PlanStatus.failed, failure: e.kind);
    }
  }
}

/// The planner.
final plannerProvider = NotifierProvider<PlannerNotifier, PlannerState>(
  PlannerNotifier.new,
);
