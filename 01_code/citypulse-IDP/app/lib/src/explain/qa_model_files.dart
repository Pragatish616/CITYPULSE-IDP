/// Where the route-question model file is (io platforms only). ADR-035, PREREGISTRATION_QA.md addendum 5.
///
/// Order: a path given at build time; on Android the file the app extracts from its own bundle (or one placed by hand in the app's
/// files folder), through a small native channel; on a desktop the `models` folder next to the program, then the project's own
/// `data/models` folder when run from a checkout. Nothing is downloaded: the file is either there or the labeler has no reply.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// The file name the app looks for.
const String kQaModelFileName = 'route_qa.gguf';

/// A model path given at build time (`--dart-define=CITYPULSE_QA_MODEL_PATH=...`), for development.
const String _override = String.fromEnvironment('CITYPULSE_QA_MODEL_PATH');

const MethodChannel _channel = MethodChannel('citypulse/qa_model');

/// The model file to use, or `null` when there is none.
Future<String?> findQaModelFile() async {
  if (_override.isNotEmpty && File(_override).existsSync()) return _override;
  if (Platform.isAndroid) {
    try {
      final path = await _channel.invokeMethod<String>('modelPath');
      if (path != null && File(path).existsSync()) return path;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    return null;
  }
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final sep = Platform.pathSeparator;
  final candidates = <String>[
    '$exeDir${sep}models$sep$kQaModelFileName',
    '${Directory.current.path}${sep}models$sep$kQaModelFileName',
    // From a checkout (flutter run in app/, tests): the project's own model folder.
    '${Directory.current.path}$sep..${sep}data${sep}models${sep}route_qa_run1_q4_k_m.gguf',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}
