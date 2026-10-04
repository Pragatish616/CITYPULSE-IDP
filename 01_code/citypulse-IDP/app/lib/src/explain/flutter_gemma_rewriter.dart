/// The Tier 1 on-device SLM rewriter (T4.3, `docs/IMPLEMENTATION_PLAN.md`) --
/// Gemma 3 270M IT, INT4-QAT, via LiteRT-LM through `flutter_gemma`
/// (`docs/DECISIONS.md` ADR-004).
///
/// **Honest limitation -- read this before touching this file, and before
/// citing it as evidence of anything (`CLAUDE.md` §4, §8.4).** This class
/// wires up `flutter_gemma`'s real published "Modern API" (package
/// `flutter_gemma`, v1.8.3 on pub.dev as of 2026-09-18 --
/// `FlutterGemma.getActiveModel`, `InferenceModel.createChat`,
/// `InferenceChat.addQueryChunk` / `generateChatResponse`, `Message.text`)
/// and is structurally correct against that documented API surface. It has
/// **never been run against real model weights** in this environment:
/// there is no Android device or emulator here, `docs/IMPLEMENTATION_PLAN
/// .md` T0.1's physical-device benchmark has not happened yet
/// (`CLAUDE.md` §4 lists it as still blocked on a human with a physical
/// device in hand), and no Gemma 3 270M IT INT4-QAT GGUF/LiteRT asset has
/// been downloaded or verified reachable from here. **Do not read this
/// class's existence as "on-device inference verified working" -- it is
/// not**, and nothing in this task's test suite exercises this class
/// against a real model; `FakeSlmRewriter`
/// (`app/test/fixtures/fake_slm_rewriter.dart`) is what exercises the
/// rewrite pipeline in this codebase's tests instead.
///
/// **A second, narrower uncertainty, disclosed rather than papered over:**
/// the exact runtime type `InferenceChat.generateChatResponse()` resolves
/// to (a bare `String`, or a wrapper object with a `.text` getter) could not
/// be confirmed against a live run either -- [_extractText] below handles
/// both shapes defensively and throws a descriptive [StateError] (never a
/// silent wrong answer) if a future package version returns something else
/// again. Whoever first runs this against a real device (T0.1) should
/// delete this paragraph once confirmed.
library;

import 'package:citypulse_app/src/explain/fact_set.dart';
import 'package:citypulse_app/src/explain/slm_rewriter.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// See this library's top-level doc comment for exactly what is and is not
/// verified about this class.
class FlutterGemmaRewriter implements SlmRewriter {
  /// Creates a rewriter against an already-installed model. Model
  /// installation (`FlutterGemma.installModel(...).fromNetwork(...)
  /// .install()`) is a one-time, network-requiring, user-consented download
  /// (ADR-005's storage budget explicitly makes the model an optional
  /// download, not something shipped by default) -- deliberately not
  /// triggered from inside a per-query rewriter, so it is not done here.
  FlutterGemmaRewriter({this.maxTokens = 512});

  /// Passed to `FlutterGemma.getActiveModel`. Kept small: Tier 1's whole
  /// point (ADR-004) is rewriting a closed, short fact set into a sentence
  /// or two, not open-ended generation.
  final int maxTokens;

  @override
  int get tier => 1;

  @override
  Future<String> generate(FactSet factSet) async {
    final model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);
    final chat = await model.createChat();
    await chat.addQueryChunk(
      Message.text(text: _buildPrompt(factSet), isUser: true),
    );
    final response = await chat.generateChatResponse();
    return _extractText(response);
  }

  /// ADR-004: "prompt = the fact set only." No trace field beyond what
  /// [FactSet] already redacted is ever concatenated into this string.
  String _buildPrompt(FactSet factSet) =>
      'You are rewriting a route explanation for a hazard-aware navigation '
      'app. Using ONLY the facts in the JSON object below -- '
      'never invent a street name, a number, or a hazard that is not '
      'present here -- write one or two short, plain sentences a driver can '
      'read at a glance. Never state or imply that any road, route, or '
      'edge is "safe", "clear", or "passable".\n\n'
      'FACTS:\n${factSet.toJson()}';

  /// Narrows whatever `generateChatResponse()` returns to plain text -- see
  /// this file's top-level doc comment on why this cannot be pinned down
  /// more precisely without a real device run.
  String _extractText(Object? response) {
    if (response is String) return response;
    final dynamicResponse = response as dynamic;
    try {
      final text = dynamicResponse.text;
      if (text is String) return text;
    } on NoSuchMethodError {
      // Falls through to the descriptive StateError below.
    }
    throw StateError(
      'FlutterGemmaRewriter: unrecognised generateChatResponse() return '
      'type ${response.runtimeType} -- this must be updated once this '
      'class has actually been run against a real flutter_gemma model '
      '(see this file\'s top-level doc comment; T0.1, docs/'
      'IMPLEMENTATION_PLAN.md).',
    );
  }
}
