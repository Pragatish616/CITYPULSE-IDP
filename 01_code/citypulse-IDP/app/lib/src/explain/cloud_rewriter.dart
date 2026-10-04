/// The Tier 2 cloud rewriter (`docs/DECISIONS.md` ADR-004, ADR-005).
///
/// It does not talk to Groq. It posts the redacted [FactSet] to the project's
/// own `router_api` `POST /rewrite`, which holds the API key and the fixed
/// prompt (KNOWN_FLAWS F-16, PLAN.md M1.9). Nothing here can carry a key, so
/// no build of the app can ship one. Without a configured server address,
/// [isAvailable] is `false` and [generate] throws; `rewrite_pipeline.dart`'s
/// [attemptRewrite] falls back to the Tier 0 template on any exception, so an
/// unavailable cloud tier is never a crash.
///
/// The reply is untrusted text: the caller must run it through the verifier
/// before showing it, exactly as for the on-device tier (ADR-004).
library;

import 'dart:async';
import 'dart:convert';

import 'package:citypulse_app/src/core/app_config.dart';
import 'package:citypulse_app/src/explain/fact_set.dart';
import 'package:citypulse_app/src/explain/slm_rewriter.dart';
import 'package:http/http.dart' as http;

/// ADR-005's cloud enrichment deadline, applied at the HTTP call itself (the
/// pipeline also wraps the whole attempt in its own timeout).
const Duration kCloudRewriterTimeout = Duration(milliseconds: 1500);

/// Tier 2 rewriter that asks the project's rewrite proxy.
class CloudRewriter implements SlmRewriter {
  /// Creates a rewriter for the `router_api` at [routerApiUrl]. A null or empty
  /// address leaves the tier unavailable.
  CloudRewriter({
    required String? routerApiUrl,
    http.Client? httpClient,
    this.timeout = kCloudRewriterTimeout,
  }) : _endpoint = routerApiUrl == null || routerApiUrl.isEmpty
           ? null
           : AppConfig.join(routerApiUrl, 'rewrite'),
       _http = httpClient ?? http.Client();

  final Uri? _endpoint;
  final http.Client _http;

  /// Per-request deadline.
  final Duration timeout;

  /// Whether a proxy address is configured. This says nothing about whether
  /// the proxy itself has a key; an unconfigured proxy answers 503 and the
  /// pipeline falls back to Tier 0.
  bool get isAvailable => _endpoint != null;

  @override
  int get tier => 2;

  @override
  Future<String> generate(FactSet factSet) async {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError(
        'CloudRewriter: no router_api address configured; the cloud tier is '
        'unavailable.',
      );
    }
    final http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'facts': factSet.toJson()}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw StateError(
        'CloudRewriter: no answer within ${timeout.inMilliseconds} ms.',
      );
    }
    if (response.statusCode != 200) {
      throw StateError('CloudRewriter: proxy answered ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    final text = decoded is Map ? decoded['text'] : null;
    if (text is! String || text.isEmpty) {
      throw StateError('CloudRewriter: proxy reply had no text.');
    }
    return text;
  }

  /// Releases the HTTP client.
  void close() => _http.close();
}
