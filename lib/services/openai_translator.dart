import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/bubble.dart';
import 'api_json.dart';
import 'bubble_parser.dart';
import 'page_translator.dart';
import 'settings_store.dart';
import 'translate_prompt.dart';

class OpenAiTranslator implements PageTranslator {
  OpenAiTranslator({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<Bubble>> translatePage({
    required SettingsStore settings,
    required Uint8List jpegBytes,
    required int imageWidth,
    required int imageHeight,
  }) async {
    _validate(settings);
    final text = await completeOpenAiChat(
      client: _client,
      baseUrl: settings.openaiBaseUrl,
      model: settings.openaiModel,
      apiKey: settings.openaiApiKey,
      prompt: buildTranslatePrompt(
        settings.targetLanguage,
        imageWidth,
        imageHeight,
      ),
      jpegBytes: jpegBytes,
      timeout: const Duration(seconds: 90),
      label: 'OpenAI',
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
    return completeOpenAiChat(
      client: _client,
      baseUrl: settings.openaiBaseUrl,
      model: settings.openaiModel,
      apiKey: settings.openaiApiKey,
      prompt: 'Reply with the single word OK.',
      timeout: const Duration(seconds: 20),
      label: 'OpenAI',
      jsonMode: false,
    );
  }

  void _validate(SettingsStore settings) {
    if (settings.openaiApiKey.isEmpty) {
      throw TranslatorException('尚未設定 OpenAI API Key');
    }
    if (settings.openaiModel.trim().isEmpty) {
      throw TranslatorException('尚未填寫 OpenAI 模型名稱');
    }
  }
}

bool isOpenAiCompatibleUrl(String baseUrl) {
  final normalized = baseUrl.trim().toLowerCase();
  return normalized.contains('/chat/completions') ||
      normalized.contains('/v1');
}

Uri buildOpenAiChatUri(String baseUrl) {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.contains('/chat/completions')) return Uri.parse(base);
  return Uri.parse('$base/chat/completions');
}

String? openAiMessageText(Map<String, dynamic> json) {
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final message = first['message'];
  if (message is! Map) return null;
  final refusal = message['refusal'];
  if (refusal is String && refusal.trim().isNotEmpty) return null;
  return _contentText(message['content']);
}

Future<String> completeOpenAiChat({
  required http.Client client,
  required String baseUrl,
  required String model,
  required String apiKey,
  required String prompt,
  required String label,
  Uint8List? jpegBytes,
  Duration timeout = const Duration(seconds: 90),
  bool jsonMode = true,
}) async {
  final uri = buildOpenAiChatUri(baseUrl);
  final content = <Map<String, dynamic>>[
    {'type': 'text', 'text': prompt},
    if (jpegBytes != null)
      {
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/jpeg;base64,${base64Encode(jpegBytes)}',
        },
      },
  ];
  final body = <String, dynamic>{
    'model': model,
    'messages': [
      {
        'role': 'user',
        'content': jpegBytes == null ? prompt : content,
      },
    ],
    'temperature': 0.2,
    'max_tokens': 8192,
    if (jsonMode) 'response_format': {'type': 'json_object'},
  };

  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  late http.Response response;
  try {
    response = await client
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(timeout);
  } on Exception catch (e) {
    throw TranslatorException('連線 $label 失敗：$e');
  }

  final decoded = decodeJsonMap(response.body);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw TranslatorException(
      jsonErrorMessage(decoded) ?? 'HTTP ${response.statusCode}',
    );
  }

  final text = openAiMessageText(decoded)?.trim();
  if (text == null || text.isEmpty) {
    throw TranslatorException('模型沒有回傳內容');
  }
  return text;
}

String? _contentText(dynamic content) {
  if (content is String) return content;
  if (content is! List) return null;
  final buffer = StringBuffer();
  for (final part in content) {
    if (part is String) {
      buffer.write(part);
    } else if (part is Map && part['text'] != null) {
      buffer.write(part['text']);
    }
  }
  return buffer.toString();
}
