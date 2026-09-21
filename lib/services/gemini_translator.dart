import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/bubble.dart';
import 'api_json.dart';
import 'bubble_parser.dart';
import 'page_translator.dart';
import 'settings_store.dart';
import 'translate_prompt.dart';

class GeminiTranslator implements PageTranslator {
  GeminiTranslator({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<Bubble>> translatePage({
    required SettingsStore settings,
    required Uint8List jpegBytes,
    required int imageWidth,
    required int imageHeight,
  }) async {
    _validate(settings);

    final uri = buildGeminiUri(
      settings.geminiBaseUrl,
      settings.geminiModel,
      settings.geminiApiKey,
    );
    final prompt = buildTranslatePrompt(
      settings.targetLanguage,
      imageWidth,
      imageHeight,
    );
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(jpegBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 8192,
        'responseMimeType': 'application/json',
      },
      'safetySettings': [
        {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_ONLY_HIGH'},
        {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_ONLY_HIGH'},
        {
          'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'threshold': 'BLOCK_ONLY_HIGH',
        },
        {
          'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_ONLY_HIGH',
        },
      ],
    });

    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': settings.geminiApiKey,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 90));
    } on Exception catch (e) {
      throw TranslatorException('連線 Gemini 失敗：$e');
    }

    final decoded = decodeJsonMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = jsonErrorMessage(decoded) ?? 'HTTP ${response.statusCode}';
      throw TranslatorException(message);
    }

    final text = geminiCandidateText(decoded);
    if (text == null || text.trim().isEmpty) {
      throw TranslatorException(_blockReason(decoded) ?? '模型沒有回傳內容');
    }

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
    final uri = buildGeminiUri(
      settings.geminiBaseUrl,
      settings.geminiModel,
      settings.geminiApiKey,
    );
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': settings.geminiApiKey,
          },
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': 'Reply with the single word OK.'},
                ],
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = decodeJsonMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TranslatorException(
        jsonErrorMessage(decoded) ?? 'HTTP ${response.statusCode}',
      );
    }
    return geminiCandidateText(decoded)?.trim() ?? 'OK';
  }

  void _validate(SettingsStore settings) {
    if (settings.geminiApiKey.isEmpty) {
      throw TranslatorException('尚未設定 Gemini API Key');
    }
    if (settings.geminiModel.trim().isEmpty) {
      throw TranslatorException('尚未填寫 Google 模型名稱');
    }
  }

  String? _blockReason(Map<String, dynamic> json) {
    final feedback = json['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      return '內容被安全過濾：${feedback['blockReason']}';
    }
    final candidates = json['candidates'];
    if (candidates is List && candidates.isNotEmpty && candidates.first is Map) {
      final reason = (candidates.first as Map)['finishReason'];
      if (reason != null && reason != 'STOP') {
        return '模型中止：$reason';
      }
    }
    return null;
  }
}

Uri buildGeminiUri(String baseUrl, String model, String apiKey) {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final uri = base.contains(':generateContent')
      ? Uri.parse(base)
      : Uri.parse('$base/models/$model:generateContent');
  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      'key': apiKey,
    },
  );
}

String? geminiCandidateText(Map<String, dynamic> json) {
  final candidates = json['candidates'];
  if (candidates is! List || candidates.isEmpty) return null;
  final first = candidates.first;
  if (first is! Map) return null;
  final content = first['content'];
  if (content is! Map) return null;
  final parts = content['parts'];
  if (parts is! List) return null;
  final buffer = StringBuffer();
  for (final part in parts) {
    if (part is Map && part['text'] != null) {
      buffer.write(part['text']);
    }
  }
  return buffer.toString();
}
