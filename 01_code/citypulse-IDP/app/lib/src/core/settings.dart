/// User preferences, persisted with `shared_preferences`.
///
/// Nothing here identifies a person. The only identifier is a random install
/// code (see [InstallId]) used to rate-limit and de-duplicate reports; the user
/// can reset it at any time (DPDP Act 2023, PLAN.md §12).
library;

import 'package:citypulse_app/src/core/city.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Where routes are calculated.
enum ComputeMode {
  /// Device on a phone, server on the web.
  auto,

  /// In-process on this device (works offline once installed).
  device,

  /// On `router_api`.
  server,
}

/// The persisted settings.
class AppSettings {
  /// Creates settings.
  const AppSettings({
    this.language = AppLanguage.en,
    this.travel = TravelType.commuter,
    this.compute = ComputeMode.auto,
    this.showHazard = true,
    this.showWatchlist = false,
  });

  /// UI language.
  final AppLanguage language;

  /// Selected travel type.
  final TravelType travel;

  /// Where to calculate routes.
  final ComputeMode compute;

  /// Whether the hazard overlay is drawn.
  final bool showHazard;

  /// Whether watchlist candidate pins are drawn.
  final bool showWatchlist;

  /// A copy with some fields replaced.
  AppSettings copyWith({
    AppLanguage? language,
    TravelType? travel,
    ComputeMode? compute,
    bool? showHazard,
    bool? showWatchlist,
  }) => AppSettings(
    language: language ?? this.language,
    travel: travel ?? this.travel,
    compute: compute ?? this.compute,
    showHazard: showHazard ?? this.showHazard,
    showWatchlist: showWatchlist ?? this.showWatchlist,
  );
}

/// The shared-preferences instance; overridden in `main` and in tests.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPreferencesProvider'),
);

/// Owns [AppSettings].
class SettingsNotifier extends Notifier<AppSettings> {
  static const _language = 'settings.language';
  static const _travel = 'settings.travel';
  static const _compute = 'settings.compute';
  static const _hazard = 'settings.show_hazard';
  static const _watchlist = 'settings.show_watchlist';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final p = _prefs;
    return AppSettings(
      language: AppLanguage.fromCode(p.getString(_language)),
      travel: TravelType.fromWire(p.getString(_travel)),
      compute: ComputeMode.values.firstWhere(
        (m) => m.name == p.getString(_compute),
        orElse: () => ComputeMode.auto,
      ),
      showHazard: p.getBool(_hazard) ?? true,
      showWatchlist: p.getBool(_watchlist) ?? false,
    );
  }

  /// Sets the UI language.
  Future<void> setLanguage(AppLanguage v) async {
    state = state.copyWith(language: v);
    await _prefs.setString(_language, v.name);
  }

  /// Sets the travel type.
  Future<void> setTravel(TravelType v) async {
    state = state.copyWith(travel: v);
    await _prefs.setString(_travel, v.wire);
  }

  /// Sets where routes are calculated.
  Future<void> setCompute(ComputeMode v) async {
    state = state.copyWith(compute: v);
    await _prefs.setString(_compute, v.name);
  }

  /// Shows or hides the hazard overlay.
  Future<void> setShowHazard({required bool value}) async {
    state = state.copyWith(showHazard: value);
    await _prefs.setBool(_hazard, value);
  }

  /// Shows or hides the watchlist candidates.
  Future<void> setShowWatchlist({required bool value}) async {
    state = state.copyWith(showWatchlist: value);
    await _prefs.setBool(_watchlist, value);
  }
}

/// The current settings.
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// The current language's strings.
final stringsProvider = Provider<Strings>(
  (ref) => Strings(
    ref.watch(settingsProvider.select((s) => s.language)),
    city: ref.watch(cityProvider),
  ),
);

/// A random, per-install code attached to reports so one device cannot flood
/// the log and a user can later ask for their reports to be removed. It is not
/// derived from any device or account identifier.
class InstallId {
  const InstallId._();

  static const _key = 'install.id';

  /// The stored code, created on first use.
  static String read(SharedPreferences prefs) {
    final existing = prefs.getString(_key);
    if (existing != null) return existing;
    return _create(prefs);
  }

  /// Replaces the stored code with a fresh random one.
  static String reset(SharedPreferences prefs) => _create(prefs);

  static String _create(SharedPreferences prefs) {
    final id = const Uuid().v4();
    prefs.setString(_key, id);
    return id;
  }
}
