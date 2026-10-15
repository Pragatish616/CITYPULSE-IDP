/// Builds the on-device question labeler where the platform can run one (Android and desktop); the web build has none.
library;

export 'question_labeler_factory_stub.dart'
    if (dart.library.io) 'question_labeler_factory_io.dart';
