/// Server-side proxy for the Tier 2 explanation rewriter (KNOWN_FLAWS F-16,
/// PLAN.md M1.9).
///
/// The Groq API key lives in this process's environment, never in an app or a
/// web bundle. A client sends only the structured fact set from its decision
/// trace; the system prompt, model, temperature and token limit are fixed
/// here, so the endpoint cannot be used as a general-purpose LLM relay. The
/// reply is plain text that the client must still pass through its verifier
/// (ADR-004) before showing it: this proxy adds no trust.
///
/// Privacy (ADR-007): the fact set carries street names, durations and report
/// ages, no coordinates and no device identifier; request bodies are not
/// logged. Per-address counters are kept in memory only.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Groq's OpenAI-compatible chat completions endpoint.
final Uri kGroqChatCompletionsUri = Uri.parse(
  'https://api.groq.com/openai/v1/chat/completions',
);

/// The fixed instruction. Mirrors the one in the app's local request builder.
const String kRewriteSystemPrompt =
    'You rewrite route explanations for a hazard-aware navigation app. '
    'Using ONLY the facts in the JSON the user provides -- never '
    'invent a street name, a number, or a hazard not present there -- write '
    'one or two short, plain sentences a driver can read at a glance. Never '
    'state or imply that any road, route, or edge is "safe", "clear", or '
    '"passable".';

/// Result of one proxy call.
sealed class RewriteResult {
  const RewriteResult();
}

/// The model's text.
class RewriteText extends RewriteResult {
  /// Wraps [text].
  const RewriteText(this.text);

  /// The rewritten explanation, unverified.
  final String text;
}

/// A refusal or failure with the HTTP status to return.
class RewriteError extends RewriteResult {
  /// Creates an error.
  const RewriteError(this.status, this.code, this.message);

  /// HTTP status.
  final int status;

  /// Stable machine-readable code.
  final String code;

  /// Human-readable message (never contains the key or the model output).
  final String message;
}

/// Calls Groq on behalf of clients, with limits.
class RewriteProxy {
  /// Creates a proxy. With a null or empty [apiKey] every call answers
  /// `rewrite_unavailable` (the Tier 2 path is simply off).
  RewriteProxy({
    required String? apiKey,
    http.Client? client,
    this.model = 'llama-3.1-8b-instant',
    this.maxFactsChars = 4096,
    this.perClientPerMinute = 10,
    this.globalPerMinute = 120,
    this.upstreamTimeout = const Duration(milliseconds: 1500),
    DateTime Function()? now,
  }) : _apiKey = apiKey,
       _client = client ?? http.Client(),
       _now = now ?? (() => DateTime.now().toUtc());

  final String? _apiKey;
  final http.Client _client;
  final DateTime Function() _now;

  /// Groq model id.
  final String model;

  /// Largest accepted fact-set JSON, in characters.
  final int maxFactsChars;

  /// Calls allowed per client address per minute.
  final int perClientPerMinute;

  /// Calls allowed in total per minute, whoever asks.
  final int globalPerMinute;

  /// Deadline for the upstream call (ADR-005).
  final Duration upstreamTimeout;

  final Map<String, List<DateTime>> _hits = {};
  final List<DateTime> _all = [];

  /// Whether a key is configured.
  bool get isConfigured => _apiKey != null && _apiKey.isNotEmpty;

  bool _allow(String client) {
    final cutoff = _now().subtract(const Duration(minutes: 1));
    _all.removeWhere((t) => t.isBefore(cutoff));
    final mine = (_hits[client] ??= [])..removeWhere((t) => t.isBefore(cutoff));
    // Forget addresses that have gone quiet so the map cannot grow forever.
    if (_hits.length > 5000) {
      _hits.removeWhere((_, v) => v.isEmpty || v.last.isBefore(cutoff));
    }
    if (mine.length >= perClientPerMinute || _all.length >= globalPerMinute) {
      return false;
    }
    final now = _now();
    mine.add(now);
    _all.add(now);
    return true;
  }

  /// Rewrites the explanation for [facts]; [clientKey] identifies the caller
  /// for rate limiting (an address, never logged).
  Future<RewriteResult> rewrite(
    Map<String, Object?> facts, {
    required String clientKey,
  }) async {
    if (!isConfigured) {
      return const RewriteError(
        503,
        'rewrite_unavailable',
        'The cloud rewriter is not configured.',
      );
    }
    final factsJson = jsonEncode(facts);
    if (factsJson.length > maxFactsChars) {
      return const RewriteError(413, 'too_large', 'Facts are too large.');
    }
    if (!_allow(clientKey)) {
      return const RewriteError(429, 'rate_limited', 'Too many requests.');
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            kGroqChatCompletionsUri,
            headers: {
              'authorization': 'Bearer $_apiKey',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0.2,
              'max_tokens': 200,
              'messages': [
                {'role': 'system', 'content': kRewriteSystemPrompt},
                {'role': 'user', 'content': factsJson},
              ],
            }),
          )
          .timeout(upstreamTimeout);
    } on TimeoutException {
      return const RewriteError(504, 'upstream_timeout', 'Rewriter timed out.');
    } on http.ClientException {
      return const RewriteError(502, 'upstream_error', 'Rewriter unreachable.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return RewriteError(
        502,
        'upstream_error',
        'Rewriter answered ${response.statusCode}.',
      );
    }
    try {
      final decoded = jsonDecode(response.body) as Map<String, Object?>;
      final choices = decoded['choices'] as List<Object?>?;
      final message = (choices?.first as Map<String, Object?>?)?['message'];
      final content = (message as Map<String, Object?>?)?['content'];
      if (content is String && content.trim().isNotEmpty) {
        return RewriteText(content.trim());
      }
    } on FormatException {
      // fall through
    } on TypeError {
      // fall through
    } on StateError {
      // empty choices: fall through
    }
    return const RewriteError(502, 'upstream_error', 'Unusable rewriter reply.');
  }
}
