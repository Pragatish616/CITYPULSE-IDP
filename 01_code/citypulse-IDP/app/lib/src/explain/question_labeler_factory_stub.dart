/// The web build: no on-device model, so the question box answers with the rules alone.
library;

import 'package:pulse_explain/pulse_explain.dart';

/// No labeler on this platform.
QuestionLabeler? createDeviceQuestionLabeler() => null;

/// Nothing to free.
Future<void> disposeDeviceQuestionLabeler(QuestionLabeler labeler) async {}
