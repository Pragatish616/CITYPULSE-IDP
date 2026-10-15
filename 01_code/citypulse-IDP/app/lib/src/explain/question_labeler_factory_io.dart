/// Android and desktop: the llama.cpp labeler reading the GGUF file found by `qa_model_files.dart`.
library;

import 'package:citypulse_app/src/explain/llama_question_labeler.dart';
import 'package:citypulse_app/src/explain/qa_model_files.dart';
import 'package:pulse_explain/pulse_explain.dart';

/// A labeler that loads the model on the first question (and has no reply if the file is missing).
QuestionLabeler? createDeviceQuestionLabeler() =>
    LlamaQuestionLabeler(locate: findQaModelFile);

/// Frees the model.
Future<void> disposeDeviceQuestionLabeler(QuestionLabeler labeler) async {
  if (labeler is LlamaQuestionLabeler) await labeler.dispose();
}
