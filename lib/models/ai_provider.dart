enum AiProvider {
  gemini,
  openai,
  ollama;

  String get label {
    switch (this) {
      case AiProvider.gemini:
        return 'Gemini';
      case AiProvider.openai:
        return 'OpenAI';
      case AiProvider.ollama:
        return 'Ollama';
    }
  }

  static AiProvider fromName(String? raw) {
    return AiProvider.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => AiProvider.gemini,
    );
  }
}
