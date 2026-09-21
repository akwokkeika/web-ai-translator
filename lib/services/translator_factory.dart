import 'package:http/http.dart' as http;

import '../models/ai_provider.dart';
import 'gemini_translator.dart';
import 'ollama_translator.dart';
import 'openai_translator.dart';
import 'page_translator.dart';

PageTranslator createTranslator(
  AiProvider provider, {
  http.Client? client,
}) {
  switch (provider) {
    case AiProvider.gemini:
      return GeminiTranslator(client: client);
    case AiProvider.openai:
      return OpenAiTranslator(client: client);
    case AiProvider.ollama:
      return OllamaTranslator(client: client);
  }
}
