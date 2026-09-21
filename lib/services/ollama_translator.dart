import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/bubble.dart';
import 'api_json.dart';
import 'bubble_parser.dart';
import 'openai_translator.dart';
import 'page_translator.dart';
import 'settings_store.dart';
import 'translate_prompt.dart';

class OllamaTranslator implements PageTranslator {
  OllamaTranslator({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<Bubble>> translatePage({
    required SettingsStore settings,
    required Uint8List jpegBytes,
    required int imageWidth,
    required int imageHeight,
  }) async {
    _validate(settings);
    final prompt = buildTranslatePrompt(
      settings.targetLanguage,
      imageWidth,
      imageHeight,
    );
    final text = isOpenAiCompatibleUrl(settings.ollamaBaseUrl)
        ? await completeOpenAiChat(
            client: _client,
            baseUrl: settings.ollamaBaseUrl,
            model: settings.ollamaModel,
            apiKey: settings.ollamaApiKey,
            prompt: prompt,
            jpegBytes: jpegBytes,
            timeout: const Duration(seconds: 180),
            label: 'Ollama',
          )
        : await _completeNative(
            settings: settings,
            prompt: prompt,
            jpegBytes: jpegBytes,
            timeout: const Duration(seconds: 180),
            jsonMode: true,
          );

    final json = jsonDecode(extractJsonObject(text));
    if (json is! Map<String, dynamic>) {
      throw TranslatorException('譯文 JSON 格式不正確');
    }
    return parseBubbles(
      json,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }

  @override
  Future<String> ping(SettingsStore settings) async {
    _validate(settings);
    if (isOpenAiCompatibleUrl(settings.ollamaBaseUrl)) {
      return completeOpenAiChat(
        client: _client,
        baseUrl: settings.ollamaBaseUrl,
        model: settings.ollamaModel,
        apiKey: settings.ollamaApiKey,
        prompt: 'Reply with the single word OK.',
        timeout: const Duration(seconds: 30),
        label: 'Ollama',
        jsonMode: false,
      );
    }
    return _completeNative(
      settings: settings,
      prompt: 'Reply with the single word OK.',
      timeout: const Duration(seconds: 30),
      jsonMode: false,
    );
  }

  Future<String> _completeNative({
    required SettingsStore settings,
    required String prompt,
    Uint8List? jpegBytes,
    required Duration timeout,
    required bool jsonMode,
  }) async {
    final uri = buildOllamaChatUri(settings.ollamaBaseUrl);
    final message = <String, dynamic>{
      'role': 'user',
      'content': prompt,
      if (jpegBytes != null) 'images': [base64Encode(jpegBytes)],
    };
    final body = <String, dynamic>{
      'model': settings.ollamaModel,
      'messages': [message],
      'stream': false,
      if (jsonMode) 'format': 'json',
      'options': {
        'temperature': 0.2,
        'num_predict': 8192,
      },
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (settings.ollamaApiKey.isNotEmpty)
        'Authorization': 'Bearer ${settings.ollamaApiKey}',
    };

    late http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
    } on Exception catch (e) {
      throw TranslatorException('連線 Ollama 失敗：$e');
    }

    final decoded = decodeJsonMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TranslatorException(
        jsonErrorMessage(decoded) ?? 'HTTP ${response.statusCode}',
      );
    }

    final text = ollamaMessageText(decoded)?.trim();
    if (text == null || text.isEmpty) {
      throw TranslatorException('模型沒有回傳內容');
    }
    return text;
  }

  void _validate(SettingsStore settings) {
    if (settings.ollamaBaseUrl.trim().isEmpty) {
      throw TranslatorException('尚未填寫 Ollama 位址');
    }
    if (settings.ollamaModel.trim().isEmpty) {
      throw TranslatorException('尚未填寫 Ollama 模型名稱');
    }
  }
}

Uri buildOllamaChatUri(String baseUrl) {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.endsWith('/api/chat')) return Uri.parse(base);
  if (base.endsWith('/api')) return Uri.parse('$base/chat');
  return Uri.parse('$base/api/chat');
}

String? ollamaMessageText(Map<String, dynamic> json) {
  final message = json['message'];
  if (message is Map && message['content'] != null) {
    return message['content'].toString();
  }
  final response = json['response'];
  if (response is String) return response;
  return null;
}
