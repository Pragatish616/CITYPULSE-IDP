/// Persists whether the ADR-011 first-use disclaimer has been acknowledged
/// for the *current* app version. `docs/DECISIONS.md` ADR-011: "Before
/// first use, and once per app version thereafter, the app shows an
/// unavoidable disclaimer" -- so acceptance is keyed by version, not a
/// single boolean, and a version bump must re-show it.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Abstraction so `DisclaimerGate` can be tested without the real
/// `shared_preferences` platform channel.
abstract class DisclaimerStore {
  /// Whether [appVersion] has already been acknowledged.
  Future<bool> isAcknowledged(String appVersion);

  /// Records that [appVersion] has been acknowledged.
  Future<void> acknowledge(String appVersion);
}

/// Real implementation backed by `shared_preferences` (local-only, no
/// network, no key -- fits CLAUDE.md §3's ₹0 budget rule trivially).
class SharedPreferencesDisclaimerStore implements DisclaimerStore {
  static const _keyPrefix = 'adr011_disclaimer_acknowledged_v';

  @override
  Future<bool> isAcknowledged(String appVersion) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_keyPrefix$appVersion') ?? false;
  }

  @override
  Future<void> acknowledge(String appVersion) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_keyPrefix$appVersion', true);
  }
}

/// In-memory implementation for widget tests -- no platform channel, no
/// disk, fully deterministic.
class InMemoryDisclaimerStore implements DisclaimerStore {
  /// Creates a store, optionally pre-seeded with already-acknowledged
  /// versions (for tests that need to start past the gate).
  InMemoryDisclaimerStore({Set<String>? acknowledgedVersions})
    : _acknowledged = {...?acknowledgedVersions};

  final Set<String> _acknowledged;

  @override
  Future<bool> isAcknowledged(String appVersion) async =>
      _acknowledged.contains(appVersion);

  @override
  Future<void> acknowledge(String appVersion) async {
    _acknowledged.add(appVersion);
  }
}
