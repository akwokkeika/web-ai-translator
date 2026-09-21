import 'dart:typed_data';

import '../models/bubble.dart';
import 'settings_store.dart';

class TranslatorException implements Exception {
  TranslatorException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class PageTranslator {
  Future<List<Bubble>> translatePage({
    required SettingsStore settings,
    required Uint8List jpegBytes,
    required int imageWidth,
    required int imageHeight,
  });

  Future<String> ping(SettingsStore settings);
}
