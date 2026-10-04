/// Hybrid Logical Clock (HLC), per Kulkarni, Demirbas, Madappa, Avva & Leone,
/// "Logical Physical Clocks and Consistent Snapshots in Globally Distributed
/// Databases" (2014) -- the algorithm ADR-008 names ("hybrid-logical-clock
/// stamps"). Pure and dependency-free: this file touches no storage or
/// network code so it can be unit-tested in isolation (T5.4).
///
/// An HLC timestamp is a triple `(logical, counter, nodeId)`:
/// - `logical` is a physical-time component (milliseconds since the Unix
///   epoch, UTC) that only ever moves forward -- it tracks `max(physical
///   time seen so far)`, not the raw clock reading, which is what gives HLC
///   its "logical" half.
/// - `counter` disambiguates multiple events that land in the same
///   `logical` millisecond (either because the physical clock did not tick,
///   or because a received remote stamp shares the same `logical` value).
/// - `nodeId` breaks ties between two different nodes that independently
///   reach the same `(logical, counter)` pair, and lets a reader attribute a
///   stamp to the device that produced it.
///
/// `HlcTimestamp` values totally order (`Comparable`) in `(logical, counter,
/// nodeId)` lexicographic order, which is exactly the order the HLC paper's
/// own `<` relation on timestamps defines (Algorithm 1's comparison is
/// logical-then-counter; `nodeId` is this implementation's deterministic
/// tie-break for the case the paper leaves to the implementer).
library;

import 'package:flutter/foundation.dart' show immutable;

/// Default [HybridLogicalClock.maxDriftMs]: five minutes, in milliseconds.
/// A plain `int` constant (rather than `Duration(minutes: 5).inMilliseconds`)
/// because `Duration.inMilliseconds` is not a `const`-evaluable getter.
const int _kDefaultMaxDriftMs = 5 * 60 * 1000;

/// A single HLC timestamp. Immutable value type.
@immutable
final class HlcTimestamp implements Comparable<HlcTimestamp> {
  /// Creates a timestamp directly from its three components. Most callers
  /// should instead get one from [HybridLogicalClock.now]/`.update` or parse
  /// one with [HlcTimestamp.parse].
  const HlcTimestamp({
    required this.logical,
    required this.counter,
    required this.nodeId,
  });

  /// Parses [encode]'s wire format back into an [HlcTimestamp]. Throws
  /// [FormatException] if [value] is not in that format.
  factory HlcTimestamp.parse(String value) {
    final parts = value.split('/');
    if (parts.length != 3) {
      throw FormatException(
        'expected an ISO-8601 timestamp, a counter and a node id joined by '
        '"/", got "$value"',
      );
    }
    final DateTime parsedTime;
    try {
      parsedTime = DateTime.parse(parts[0]);
    } on FormatException {
      throw FormatException('invalid HLC logical timestamp in "$value"');
    }
    final counter = int.tryParse(parts[1]);
    if (counter == null) {
      throw FormatException('invalid HLC counter in "$value"');
    }
    return HlcTimestamp(
      logical: parsedTime.toUtc().millisecondsSinceEpoch,
      counter: counter,
      nodeId: parts[2],
    );
  }

  /// Milliseconds since the Unix epoch (UTC) -- the HLC's physical-time
  /// component. Monotonically non-decreasing across every timestamp a given
  /// [HybridLogicalClock] instance produces or merges.
  final int logical;

  /// Disambiguates events sharing the same [logical] value.
  final int counter;

  /// The device/client id that produced this timestamp -- the final
  /// tie-break when two timestamps share `(logical, counter)`.
  final String nodeId;

  /// The wire format: [logical] as an ISO-8601 UTC timestamp, then the
  /// zero-padded (to 10 decimal digits) [counter], then [nodeId], joined by
  /// `/`. That separator is used because an ISO-8601 timestamp never
  /// contains it (unlike `-`, `:`, or `.`), so parsing is an unambiguous
  /// three-way split. Zero-padding the counter keeps the encoded string
  /// itself lexicographically sortable in step with [compareTo], which is a
  /// useful property for callers that store the encoded form (e.g. as a
  /// JSON string) and want cheap ordering without decoding first.
  String encode() {
    final iso = DateTime.fromMillisecondsSinceEpoch(
      logical,
      isUtc: true,
    ).toIso8601String();
    final paddedCounter = counter.toString().padLeft(10, '0');
    return '$iso/$paddedCounter/$nodeId';
  }

  @override
  int compareTo(HlcTimestamp other) {
    if (logical != other.logical) {
      return logical.compareTo(other.logical);
    }
    if (counter != other.counter) {
      return counter.compareTo(other.counter);
    }
    return nodeId.compareTo(other.nodeId);
  }

  /// Whether this timestamp orders strictly before [other].
  bool operator <(HlcTimestamp other) => compareTo(other) < 0;

  /// Whether this timestamp orders at or before [other].
  bool operator <=(HlcTimestamp other) => compareTo(other) <= 0;

  /// Whether this timestamp orders strictly after [other].
  bool operator >(HlcTimestamp other) => compareTo(other) > 0;

  /// Whether this timestamp orders at or after [other].
  bool operator >=(HlcTimestamp other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HlcTimestamp &&
          other.logical == logical &&
          other.counter == counter &&
          other.nodeId == nodeId);

  @override
  int get hashCode => Object.hash(logical, counter, nodeId);

  @override
  String toString() => 'HlcTimestamp(${encode()})';
}

/// Raised by [HybridLogicalClock.update] when a remote timestamp's
/// [HlcTimestamp.logical] component is further ahead of this node's own
/// physical clock than [HybridLogicalClock.maxDriftMs] tolerates.
///
/// Per the HLC paper §4 ("Bounded Clock Skew"): assuming the underlying
/// physical clocks are within `epsilon` of each other, `logical - physical
/// time` stays bounded by `epsilon` for legitimate stamps -- a remote
/// timestamp that violates a generous bound is far more likely to be a
/// misconfigured clock or a malicious/corrupt payload than a real event, so
/// this is surfaced as an error rather than silently accepted (which would
/// let one bad clock permanently drag every node's HLC forward).
class ClockSkewException implements Exception {
  /// Creates the exception with a human-readable [message].
  ClockSkewException(this.message);

  /// Describes which remote timestamp was rejected and by how much.
  final String message;

  @override
  String toString() => 'ClockSkewException: $message';
}

/// A single node's HLC state machine. One instance per device -- it is
/// mutable (deliberately: an HLC's whole point is that each event advances a
/// running local state, per the paper's Algorithm 1), so callers needing
/// concurrency safety should serialize calls to [now] and [update]
/// themselves (the sync client in this package is single-threaded per sync
/// pass, so it does not need to).
class HybridLogicalClock {
  /// Creates a clock for [nodeId]. [physicalTimeMs] defaults to the real
  /// wall clock (`DateTime.now().toUtc()`); tests inject a fake one to
  /// exercise skew/tie behaviour deterministically. [maxDriftMs] defaults to
  /// [_kDefaultMaxDriftMs].
  HybridLogicalClock({
    required this.nodeId,
    int Function()? physicalTimeMs,
    this.maxDriftMs = _kDefaultMaxDriftMs,
  }) : _physicalTimeMs = physicalTimeMs ?? _defaultPhysicalTimeMs;

  /// This device's id -- embedded in every [HlcTimestamp] this clock
  /// produces, per ADR-008 ("client-generated ... hybrid-logical-clock
  /// stamps").
  final String nodeId;

  /// How the clock reads "physical now", in milliseconds since the Unix
  /// epoch (UTC). A closure, not a direct `DateTime.now()` call, so tests
  /// can inject a fake clock to exercise skew/tie behaviour deterministically
  /// (`docs/IMPLEMENTATION_PLAN.md` T5.4: "correct merge-on-receive
  /// behavior, clock-skew tolerance").
  final int Function() _physicalTimeMs;

  /// The largest amount (milliseconds) a remote [HlcTimestamp.logical] may
  /// exceed this node's own physical clock reading before [update] throws
  /// [ClockSkewException] instead of adopting it. Five minutes by default --
  /// generous enough to absorb ordinary NTP-class drift and sync latency,
  /// tight enough to catch a badly wrong device clock rather than let it
  /// permanently drag this node's HLC into the future.
  final int maxDriftMs;

  int _lastLogical = 0;
  int _lastCounter = 0;

  /// The most recent timestamp this clock has produced or merged, if any.
  /// Exposed for tests and diagnostics; not required for [now]/[update]'s
  /// own correctness.
  HlcTimestamp? get last => _lastLogical == 0 && _lastCounter == 0
      ? null
      : HlcTimestamp(
          logical: _lastLogical,
          counter: _lastCounter,
          nodeId: nodeId,
        );

  /// Stamps a purely local event (e.g. a hazard report created on this
  /// device). Per Algorithm 1 ("Send Event / Local Event"):
  /// `l' = max(l, physicalTime)`; if the physical clock actually advanced
  /// past the previous `l`, the counter resets to 0, otherwise it increments
  /// -- which is exactly what gives two `now()` calls made within the same
  /// millisecond (or with a stalled/backwards-jumping physical clock)
  /// strictly increasing timestamps: monotonicity on local events, without
  /// depending on the physical clock's own resolution or monotonicity.
  HlcTimestamp now() {
    final physical = _physicalTimeMs();
    if (physical > _lastLogical) {
      _lastLogical = physical;
      _lastCounter = 0;
    } else {
      _lastCounter += 1;
    }
    return HlcTimestamp(
      logical: _lastLogical,
      counter: _lastCounter,
      nodeId: nodeId,
    );
  }

  /// Merges a [remote] timestamp received from another node (e.g. an
  /// observation pulled from the server that another device originally
  /// reported) into this clock's state, per Algorithm 1's "Receive Event".
  ///
  /// Returns the new local timestamp for this receive event itself. Throws
  /// [ClockSkewException] if `remote.logical` is more than [maxDriftMs] past
  /// this node's own physical clock -- see that class's doc comment.
  HlcTimestamp update(HlcTimestamp remote) {
    final physical = _physicalTimeMs();

    if (remote.logical - physical > maxDriftMs) {
      throw ClockSkewException(
        'remote HLC logical time ${remote.logical} is '
        '${remote.logical - physical}ms ahead of local physical time '
        '$physical, exceeding maxDriftMs=$maxDriftMs',
      );
    }

    final newLogical = [
      _lastLogical,
      remote.logical,
      physical,
    ].reduce((a, b) => a > b ? a : b);

    final int newCounter;
    if (newLogical == _lastLogical && newLogical == remote.logical) {
      // Both sides already sit at the winning logical time: counters must
      // merge, not just carry one side forward, or two nodes racing at the
      // same logical instant could each pick a counter the other has
      // already used.
      newCounter =
          (_lastCounter > remote.counter ? _lastCounter : remote.counter) + 1;
    } else if (newLogical == _lastLogical) {
      newCounter = _lastCounter + 1;
    } else if (newLogical == remote.logical) {
      newCounter = remote.counter + 1;
    } else {
      // The physical clock itself is the new maximum -- a fresh instant
      // neither side has stamped an event at yet.
      newCounter = 0;
    }

    _lastLogical = newLogical;
    _lastCounter = newCounter;
    return HlcTimestamp(
      logical: _lastLogical,
      counter: _lastCounter,
      nodeId: nodeId,
    );
  }
}

int _defaultPhysicalTimeMs() => DateTime.now().toUtc().millisecondsSinceEpoch;
