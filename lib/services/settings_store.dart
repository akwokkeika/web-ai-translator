import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_provider.dart';

class SettingsStore extends ChangeNotifier {
  static const defaultGeminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';
  static const defaultOpenAiBaseUrl = 'https://api.openai.com/v1';
  static const defaultOllamaBaseUrl = 'http://127.0.0.1:11434';
  static const defaultLanguage = '繁體中文';
  static const defaultMinFontPx = 20;
  static const minFontPxFloor = 8;
  static const minFontPxCeil = 64;

  static const languages = [
    '繁體中文',
    '简体中文',
    'English',
    '한국어',
    '日本語',
    'Tiếng Việt',
  ];

  AiProvider provider = AiProvider.gemini;

  String geminiApiKey = '';
  String geminiModel = '';
  String geminiBaseUrl = defaultGeminiBaseUrl;

  String openaiApiKey = '';
  String openaiModel = '';
  String openaiBaseUrl = defaultOpenAiBaseUrl;

  String ollamaApiKey = '';
  String ollamaModel = '';
  String ollamaBaseUrl = defaultOllamaBaseUrl;

  String targetLanguage = defaultLanguage;
  int minFontPx = defaultMinFontPx;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    provider = AiProvider.fromName(prefs.getString('ai_provider'));
    geminiApiKey = prefs.getString('gemini_api_key') ?? '';
    geminiModel = prefs.getString('gemini_model') ?? '';
    geminiBaseUrl = prefs.getString('gemini_base_url') ?? defaultGeminiBaseUrl;
    openaiApiKey = prefs.getString('openai_api_key') ?? '';
    openaiModel = prefs.getString('openai_model') ?? '';
    openaiBaseUrl = prefs.getString('openai_base_url') ?? defaultOpenAiBaseUrl;
    ollamaApiKey = prefs.getString('ollama_api_key') ?? '';
    ollamaModel = prefs.getString('ollama_model') ?? '';
    ollamaBaseUrl = prefs.getString('ollama_base_url') ?? defaultOllamaBaseUrl;
    targetLanguage = prefs.getString('target_language') ?? defaultLanguage;
    minFontPx = clampFont(prefs.getInt('min_font_px') ?? defaultMinFontPx);
    notifyListeners();
  }

  Future<void> save({
    required AiProvider provider,
    required String geminiApiKey,
    required String geminiModel,
    required String geminiBaseUrl,
    required String openaiApiKey,
    required String openaiModel,
    required String openaiBaseUrl,
    required String ollamaApiKey,
    required String ollamaModel,
    required String ollamaBaseUrl,
    required String targetLanguage,
    required int minFontPx,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.provider = provider;
    this.geminiApiKey = geminiApiKey.trim();
    this.geminiModel = geminiModel.trim();
    this.geminiBaseUrl = _orDefault(geminiBaseUrl, defaultGeminiBaseUrl);
    this.openaiApiKey = openaiApiKey.trim();
    this.openaiModel = openaiModel.trim();
    this.openaiBaseUrl = _orDefault(openaiBaseUrl, defaultOpenAiBaseUrl);
    this.ollamaApiKey = ollamaApiKey.trim();
    this.ollamaModel = ollamaModel.trim();
    this.ollamaBaseUrl = _orDefault(ollamaBaseUrl, defaultOllamaBaseUrl);
    this.targetLanguage = targetLanguage.trim().isEmpty
        ? defaultLanguage
        : targetLanguage.trim();
    this.minFontPx = clampFont(minFontPx);
    await prefs.setString('ai_provider', this.provider.name);
    await prefs.setString('gemini_api_key', this.geminiApiKey);
    await prefs.setString('gemini_model', this.geminiModel);
    await prefs.setString('gemini_base_url', this.geminiBaseUrl);
    await prefs.setString('openai_api_key', this.openaiApiKey);
    await prefs.setString('openai_model', this.openaiModel);
    await prefs.setString('openai_base_url', this.openaiBaseUrl);
    await prefs.setString('ollama_api_key', this.ollamaApiKey);
    await prefs.setString('ollama_model', this.ollamaModel);
    await prefs.setString('ollama_base_url', this.ollamaBaseUrl);
    await prefs.setString('target_language', this.targetLanguage);
    await prefs.setInt('min_font_px', this.minFontPx);
    notifyListeners();
  }

  Future<void> setMinFontPx(int value) async {
    final prefs = await SharedPreferences.getInstance();
    minFontPx = clampFont(value);
    await prefs.setInt('min_font_px', minFontPx);
    notifyListeners();
  }

  List<String> get missingRequiredFields {
    switch (provider) {
      case AiProvider.gemini:
        return [
          if (geminiApiKey.isEmpty) 'Gemini API Key',
          if (geminiModel.isEmpty) 'Google 模型名稱',
        ];
      case AiProvider.openai:
        return [
          if (openaiApiKey.isEmpty) 'OpenAI API Key',
          if (openaiModel.isEmpty) 'OpenAI 模型名稱',
        ];
      case AiProvider.ollama:
        return [
          if (ollamaBaseUrl.isEmpty) 'Ollama 位址',
          if (ollamaModel.isEmpty) 'Ollama 模型名稱',
        ];
    }
  }

  static int clampFont(int value) =>
      value.clamp(minFontPxFloor, minFontPxCeil).toInt();

  static String _orDefault(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
}
