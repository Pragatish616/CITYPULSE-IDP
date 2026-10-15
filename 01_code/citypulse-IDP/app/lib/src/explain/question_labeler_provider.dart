/// The on-device question labeler (D1, ADR-035, PREREGISTRATION_QA.md addendum 5), or `null` when there is none.
///
/// It is `null` in every build today: no phone runtime for the model has been chosen or wired, so the question box answers with the
/// rule-based answerer (D0) alone. When a runtime exists, a measurement build will return it here behind a compile-time flag, and a
/// normal build will still return `null`. Tests override this provider with a fake.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse_explain/pulse_explain.dart';

/// The labeler the question box asks, or `null` for none.
final questionLabelerProvider = Provider<QuestionLabeler?>((ref) => null);
