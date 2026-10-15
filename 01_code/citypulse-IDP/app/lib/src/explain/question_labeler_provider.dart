/// The on-device question labeler (D1, ADR-035, PREREGISTRATION_QA.md addendum 5), or `null` when there is none.
///
/// Off unless the build asks for it: `--dart-define=CITYPULSE_QA_MODEL=true` makes a measurement build that uses the model file (see
/// `qa_model_files.dart`). A normal build never loads a model and answers with the rule-based answerer alone. The web build never has
/// one. Tests override this provider with a fake.
library;

import 'package:citypulse_app/src/explain/question_labeler_factory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse_explain/pulse_explain.dart';

/// Whether this build uses the on-device model (a measurement build). Fixed at build time.
const bool kQaModelBuild = bool.fromEnvironment('CITYPULSE_QA_MODEL');

/// Whether the "How this question was read" test panel starts open. The desktop test app sets it, so the readings are in view while
/// testing the model; everywhere else it starts closed.
final qaTraceOpenProvider = Provider<bool>((ref) => false);

/// The labeler the question box asks, or `null` for none.
final questionLabelerProvider = Provider<QuestionLabeler?>((ref) {
  if (!kQaModelBuild) return null;
  final labeler = createDeviceQuestionLabeler();
  if (labeler != null) {
    ref.onDispose(() => disposeDeviceQuestionLabeler(labeler));
  }
  return labeler;
});
