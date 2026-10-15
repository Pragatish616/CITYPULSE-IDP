/// The phone and desktop runtime for the route-question model (D1, ADR-035, PREREGISTRATION_QA.md addendum 5): llama.cpp through
/// `llamadart`, reading a GGUF file from disk. It only labels the question; see `question_labeler.dart` in `pulse_explain` for what is
/// done with the reply (read strictly, safety guard, 8-second limit, fallback to the rule-based answer).
///
/// Decoding matches how the model was evaluated: greedy (temperature 0), no repetition penalty, at most 40 new tokens, the same two chat
/// messages it was trained on. `llamadart`'s own default repeat penalty is 1.1, which the model was never evaluated with, so it is
/// switched off here.
///
/// CPU only: a phone GPU path (Vulkan) is experimental in the runtime and unsafe on some drivers, and a 0.5 B model labelling a short
/// question is quick on the CPU. This is not measured on a phone yet (addendum 3); the ceilings there decide whether it ships.
library;

import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:pulse_explain/pulse_explain.dart';

/// Labels questions with a GGUF model found by [locate].
class LlamaQuestionLabeler implements QuestionLabeler {
  /// Creates a labeler. Nothing is loaded until the first question.
  LlamaQuestionLabeler({required this.locate, this.contextSize = 512});

  /// Finds the GGUF file, or returns `null` when there is none (the labeler then has no reply and the ladder uses the rules).
  final Future<String?> Function() locate;

  /// The context window in tokens; the prompt is about 60 and the reply at most 40.
  final int contextSize;

  Future<LlamaEngine?>? _loading;
  Future<void> _tail = Future<void>.value();

  /// What the labeler is doing, for the test panel: `not loaded`, `loading`, `ready`, `model file not found`, or `failed: ...`.
  String status = 'not loaded';

  /// The path of the loaded model, once known.
  String? modelPath;

  Future<LlamaEngine?> _engine() => _loading ??= _load();

  Future<LlamaEngine?> _load() async {
    status = 'loading';
    try {
      final path = await locate();
      if (path == null) {
        status = 'model file not found';
        return null;
      }
      modelPath = path;
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.path(path)),
        params: ModelParams(
          contextSize: contextSize,
          device: ComputeDevice.cpu,
        ),
      );
      status = 'ready';
      return engine;
    } on Object catch (e) {
      status = 'failed: $e';
      return null;
    }
  }

  @override
  Future<String?> reply(String question) {
    // One question at a time: the engine holds one context.
    final run = _tail.then((_) => _generate(question));
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<String?> _generate(String question) async {
    final engine = await _engine();
    if (engine == null) return null;
    final messages = [
      for (final m in labelMessages(question))
        LlamaChatMessage.fromText(
          role: m.role == 'system' ? LlamaChatRole.system : LlamaChatRole.user,
          text: m.content,
        ),
    ];
    return engine
        .create(
          messages,
          params: const GenerationParams(
            maxTokens: 40,
            temp: 0,
            penalty: 1,
            seed: 1,
          ),
        )
        .text();
  }

  /// Frees the model.
  Future<void> dispose() async {
    final engine = await _loading;
    _loading = null;
    await engine?.dispose();
  }
}
