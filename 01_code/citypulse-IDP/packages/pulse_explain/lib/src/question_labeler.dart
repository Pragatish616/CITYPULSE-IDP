/// D1 of the route-question ladder (ADR-035, PREREGISTRATION_QA.md addenda 1 and 5): a small on-device model reads the question and
/// returns a label; the rule-based answerer (D0) still writes the answer and the verifier still checks it.
///
/// What the model can and cannot do here, by construction:
/// - It sees only the traveller's question text. It never sees the route's facts, so it cannot state one.
/// - Its reply is read by [parseModelLabel] and nothing else: a label from the 19 known intents or no label. Any other text is dropped.
/// - D0 always runs first and is the fallback: no model, no reply in time, an error or an unreadable reply gives the D0 answer.
/// - **Safety guard:** if the rule-based classifier marks the question as a safety question (main or second part) and the model's
///   label does not, the D0 answer is used. The model can add caution, never remove it. Refusals and the verifier are unchanged.
///
/// This is not adoption: D1 is adopted only by the rule in the pre-registration (sealed test set, safety bars, phone ceilings).
library;

import 'dart:async';
import 'dart:convert';

import 'package:pulse_explain/src/route_qa.dart';
import 'package:pulse_router/pulse_router.dart';

/// The system message the model was trained with (`ml/route_qa/prompts.py: SYSTEM_U`). A test keeps the two in step.
const String kLabelSystemPrompt =
    "Label the traveller's question about a route. Reply with JSON.";

/// The longest time a label is waited for before the rule-based answer is used (pre-registration addendum 3 and 5).
const Duration kLabelTimeout = Duration(seconds: 8);

/// The chat messages that ask the model to label [question]: `[(role, content), ...]`, the same two the model was trained on.
List<({String role, String content})> labelMessages(String question) => [
  (role: 'system', content: kLabelSystemPrompt),
  (role: 'user', content: question),
];

/// A label read from the model's reply.
class ModelLabel {
  /// Creates a label.
  const ModelLabel(this.intent, [this.secondary]);

  /// The main intent.
  final QaIntent intent;

  /// The second part of a two-part question, if any.
  final QaIntent? secondary;

  @override
  bool operator ==(Object other) =>
      other is ModelLabel &&
      other.intent == intent &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(intent, secondary);

  @override
  String toString() => 'ModelLabel(${intent.wireName}, ${secondary?.wireName})';
}

final RegExp _firstObject = RegExp(r'\{.*?\}', dotAll: true);

/// Reads the model's reply the way `ml/route_qa/prompts.py: parse_label` does: the first `{...}` must be valid JSON with a known
/// `intent`; `secondary` is kept only if it is a known intent different from `intent`. Anything else gives `null`: never a guess.
ModelLabel? parseModelLabel(String reply) {
  final m = _firstObject.firstMatch(reply);
  if (m == null) return null;
  final Object? obj;
  try {
    obj = jsonDecode(m.group(0)!);
  } on FormatException {
    return null;
  }
  if (obj is! Map) return null;
  final intent = _intentOf(obj['intent']);
  if (intent == null) return null;
  var secondary = _intentOf(obj['secondary']);
  if (secondary == intent) secondary = null;
  return ModelLabel(intent, secondary);
}

QaIntent? _intentOf(Object? v) {
  if (v is! String) return null;
  for (final i in QaIntent.values) {
    if (i.wireName == v) return i;
  }
  return null;
}

/// Something that turns a question into the model's raw reply text (the runtime behind it is a separate choice).
// ignore: one_member_abstracts
abstract interface class QuestionLabeler {
  /// The model's raw reply to [labelMessages] for [question], or `null` if it has none. May throw; the ladder treats that as no reply.
  Future<String?> reply(String question);
}

/// The result of the ladder for one question.
class LadderResult {
  /// Creates a result.
  const LadderResult({
    required this.answer,
    required this.usedModel,
    required this.rulesLabel,
    this.modelLabel,
    this.labelTime,
    this.note = '',
  });

  /// The answer to show. Always passed the verifier, or is the fixed fallback.
  final QaAnswer answer;

  /// Whether the model's label (and not the rule-based one) decided how the question was answered.
  final bool usedModel;

  /// How the rule-based classifier understood the question (always present: D0 runs first).
  final ModelLabel rulesLabel;

  /// The label read from the model, if any, whether or not it was used.
  final ModelLabel? modelLabel;

  /// How long the model took to reply, when a model was asked (a reply that timed out reports the time waited).
  final Duration? labelTime;

  /// Why the rule-based answer was kept, for logging and tests: `no model`, `no label`, `safety guard`, `same label`, or empty.
  final String note;
}

/// Answers [question] with the ladder: D0 first, then the model's label if there is one, a readable one arrives in [timeout], and the
/// safety guard allows it.
Future<LadderResult> answerWithLabeler({
  required String question,
  required DecisionTrace trace,
  required EventState eventState,
  required Map<String, String> hazardDisplayNouns,
  QuestionLabeler? labeler,
  Duration timeout = kLabelTimeout,
}) async {
  final rules = answerQuestion(
    question: question,
    trace: trace,
    eventState: eventState,
    hazardDisplayNouns: hazardDisplayNouns,
  );
  final c = rules.classification;
  final rulesLabel = ModelLabel(c.intent, c.secondary);
  if (labeler == null) {
    return LadderResult(
      answer: rules,
      usedModel: false,
      rulesLabel: rulesLabel,
      note: 'no model',
    );
  }
  final clock = Stopwatch()..start();
  String? reply;
  try {
    reply = await labeler.reply(question).timeout(timeout);
  } on Object {
    reply = null;
  }
  clock.stop();
  final label = reply == null ? null : parseModelLabel(reply);
  if (label == null) {
    return LadderResult(
      answer: rules,
      usedModel: false,
      rulesLabel: rulesLabel,
      labelTime: clock.elapsed,
      note: 'no label',
    );
  }
  if (label.intent == c.intent && label.secondary == c.secondary) {
    return LadderResult(
      answer: rules,
      usedModel: false,
      rulesLabel: rulesLabel,
      modelLabel: label,
      labelTime: clock.elapsed,
      note: 'same label',
    );
  }
  final rulesSafety =
      c.intent == QaIntent.isSafe || c.secondary == QaIntent.isSafe;
  final modelSafety =
      label.intent == QaIntent.isSafe || label.secondary == QaIntent.isSafe;
  if (rulesSafety && !modelSafety) {
    return LadderResult(
      answer: rules,
      usedModel: false,
      rulesLabel: rulesLabel,
      modelLabel: label,
      labelTime: clock.elapsed,
      note: 'safety guard',
    );
  }
  return LadderResult(
    answer: answerQuestion(
      question: question,
      trace: trace,
      eventState: eventState,
      hazardDisplayNouns: hazardDisplayNouns,
      forceIntent: label.intent,
      forceSecondary: label.secondary,
    ),
    usedModel: true,
    rulesLabel: rulesLabel,
    modelLabel: label,
    labelTime: clock.elapsed,
  );
}
