/// Polls the report server's `GET /context/rain` and feeds the [EventStateController] (ADR-027).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'event_state.dart';

/// Fetches the rain context on a timer.
class RainSync {
  /// Creates a poller. [baseUrl] is the report server root (the same `OBSERVATIONS_URL` the observation poller uses).
  /// [client] is injectable for tests.
  RainSync({
    required this.baseUrl,
    required this.controller,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// The report server root, with a trailing slash.
  final Uri baseUrl;

  /// Receives each result.
  final EventStateController controller;

  final http.Client _client;
  Timer? _timer;

  /// One poll. Never throws: a failure is passed to the controller, which keeps the last reading until it is too old to trust.
  /// Returns whether it succeeded.
  Future<bool> syncOnce() async {
    try {
      // The first call after a cold start makes the report server fetch six images from NASA, so allow time.
      final response = await _client
          .get(baseUrl.resolve('context/rain'))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw http.ClientException(
          'GET /context/rain returned ${response.statusCode}',
          baseUrl,
        );
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, Object?>)
        throw const FormatException('rain context is not an object');
      controller.onRain(RainSignal.fromJson(json));
      return true;
    } on Object catch (e) {
      controller.onRainFailure(e);
      return false;
    }
  }

  /// Starts polling: one poll now, then one every [every] after a success. After a failure it tries again every [retry] (a minute by
  /// default), so a router that starts before the report server is up does not wait a quarter of an hour for its first reading.
  void start({
    Duration every = const Duration(minutes: 15),
    Duration retry = const Duration(minutes: 1),
  }) {
    var lastTry = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    var lastOk = false;
    Future<void> tick() async {
      lastTry = DateTime.now().toUtc();
      lastOk = await syncOnce();
    }

    unawaited(tick());
    _timer = Timer.periodic(retry, (_) {
      final wait = lastOk ? every : retry;
      if (DateTime.now().toUtc().difference(lastTry) >=
          wait - const Duration(seconds: 1))
        unawaited(tick());
    });
  }

  /// Stops polling and closes the HTTP client.
  void stop() {
    _timer?.cancel();
    _client.close();
  }
}
