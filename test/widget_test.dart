import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:web_ai_translator/models/ai_provider.dart';
import 'package:web_ai_translator/models/bookmark.dart';
import 'package:web_ai_translator/models/bubble.dart';
import 'package:web_ai_translator/models/overlay_page.dart';
import 'package:web_ai_translator/services/bookmark_store.dart';
import 'package:web_ai_translator/services/bubble_parser.dart';
import 'package:web_ai_translator/services/gemini_translator.dart';
import 'package:web_ai_translator/services/library_backup.dart';
import 'package:web_ai_translator/services/ollama_translator.dart';
import 'package:web_ai_translator/services/openai_translator.dart';
import 'package:web_ai_translator/services/overlay_coords.dart';
import 'package:web_ai_translator/services/overlay_store.dart';
import 'package:web_ai_translator/services/page_metrics.dart';
import 'package:web_ai_translator/services/settings_store.dart';
import 'package:web_ai_translator/services/text_fit.dart';
import 'package:web_ai_translator/services/translator_factory.dart';

void main() {
  test('parse ratio coordinates', () {
    final bubbles = parseBubbles(
      jsonDecode('''
      {"bubbles":[{"original":"こんにちは","translated":"你好","x":0.1,"y":0.2,"w":0.3,"h":0.15}]}
      ''') as Map<String, dynamic>,
      imageWidth: 1000,
      imageHeight: 2000,
    );
    expect(bubbles, hasLength(1));
    expect(bubbles.first.translated, '你好');
    expect(bubbles.first.x, closeTo(0.1, 0.0001));
  });

  test('parse pixel coordinates and fenced json', () {
    final raw = extractJsonObject('''
```json
{"bubbles":[{"original":"a","translated":"b","x":100,"y":200,"w":200,"h":100}]}
```
''');
    final bubbles = parseBubbles(
      jsonDecode(raw) as Map<String, dynamic>,
      imageWidth: 1000,
      imageHeight: 1000,
    );
    expect(bubbles.first.x, closeTo(0.1, 0.0001));
    expect(bubbles.first.w, closeTo(0.2, 0.0001));
  });

  test('bookmark json roundtrip and merge', () {
    final json = encodeBookmarksJson([
      const Bookmark(id: '1', name: '站A', url: 'https://a.example/'),
    ]);
    final parsed = decodeBookmarksJson(json);
    expect(parsed.single.name, '站A');
    expect(parsed.single.url, 'https://a.example/');

    final merged = mergeBookmarks(parsed, [
      const Bookmark(id: '2', name: '站A新名', url: 'https://a.example'),
      const Bookmark(id: '3', name: '站B', url: 'https://b.example'),
    ]);
    expect(merged, hasLength(2));
    expect(
      merged.firstWhere((b) => b.url.contains('a.example')).name,
      '站A新名',
    );
  });

  test('bookmark json accepts a raw array', () {
    final parsed = decodeBookmarksJson(
      '[{"name":"x","url":"https://x.test"}]',
    );
    expect(parsed.single.name, 'x');
  });

  testWidgets('wraps at min size instead of shrinking', (tester) async {
    final size = fitBubbleFontSize(
      text: '你好世界你好世界',
      maxWidth: 120,
      maxHeight: 80,
      minFontSize: 18,
    );
    expect(size, closeTo(18, 0.2));
  });

  testWidgets('shrinks only when wrapped text still overflows', (tester) async {
    final size = fitBubbleFontSize(
      text: '這段譯文非常長而且文字框很小必須縮小才能塞進去一二三四五六七八九十',
      maxWidth: 40,
      maxHeight: 28,
      minFontSize: 20,
      floorFontSize: 8,
    );
    expect(size, lessThan(20));
    expect(size, greaterThanOrEqualTo(8));
  });

  test('overlay url key drops hash and trailing slash', () {
    expect(
      overlayUrlKey('https://a.example/ch/1/#page'),
      'https://a.example/ch/1',
    );
    expect(
      overlayUrlKey('https://a.example/ch/1?id=2'),
      'https://a.example/ch/1?id=2',
    );
  });

  test('screenshot bubbles map onto document Y using scroll metrics', () {
    const metrics = WebScrollMetrics(
      scrollX: 0,
      scrollY: 800,
      innerWidth: 400,
      innerHeight: 200,
      scrollWidth: 400,
      scrollHeight: 4000,
    );
    final overlay = overlayBubblesFromScreenshot(
      bubbles: [
        Bubble(
          original: 'a',
          translated: '你好',
          x: 0.1,
          y: 0.25,
          w: 0.4,
          h: 0.2,
        ),
      ],
      metrics: metrics,
    );
    expect(overlay, hasLength(1));
    expect(overlay.first.translated, '你好');
    expect(overlay.first.source, OverlaySource.gemini);
    expect(overlay.first.x, closeTo(0.1, 0.0001));
    expect(overlay.first.yPx, closeTo(850, 0.0001));
    expect(overlay.first.hPx, closeTo(40, 0.0001));
  });

  test('merge gemini capture keeps manual boxes in the same view', () {
    final current = [
      OverlayBubble(
        id: 'g1',
        source: OverlaySource.gemini,
        original: 'old',
        translated: '舊',
        x: 0.1,
        yPx: 820,
        w: 0.3,
        hPx: 40,
      ),
      OverlayBubble(
        id: 'm1',
        source: OverlaySource.manual,
        original: '',
        translated: '手加',
        x: 0.2,
        yPx: 830,
        w: 0.3,
        hPx: 40,
      ),
      OverlayBubble(
        id: 'g2',
        source: OverlaySource.gemini,
        original: 'far',
        translated: '遠處',
        x: 0.1,
        yPx: 2000,
        w: 0.3,
        hPx: 40,
      ),
    ];
    final captured = [
      OverlayBubble(
        id: 'new',
        source: OverlaySource.gemini,
        original: 'new',
        translated: '新',
        x: 0.15,
        yPx: 810,
        w: 0.3,
        hPx: 40,
      ),
    ];
    final merged = mergeGeminiCapture(
      current: current,
      captured: captured,
      viewTop: 800,
      viewBottom: 1000,
    );
    expect(merged.map((b) => b.id), ['m1', 'g2', 'new']);
  });

  test('overlay json roundtrip', () {
    final page = OverlayPage(
      urlKey: 'https://a.example/ch/1',
      url: 'https://a.example/ch/1#x',
      pageWidth: 400,
      scrollHeight: 3000,
      updatedAt: DateTime.utc(2026, 9, 21),
      bubbles: [
        OverlayBubble(
          id: '1',
          source: OverlaySource.manual,
          original: 'hi',
          translated: '嗨',
          x: 0.2,
          yPx: 1200,
          w: 0.4,
          hPx: 80,
        ),
      ],
    );
    final encoded = encodeOverlayPagesJson({page.urlKey: page});
    final decoded = decodeOverlayPagesJson(encoded);
    expect(decoded, hasLength(1));
    final roundtrip = decoded[page.urlKey]!;
    expect(roundtrip.bubbles.single.translated, '嗨');
    expect(roundtrip.bubbles.single.yPx, closeTo(1200, 0.0001));
    expect(roundtrip.scrollHeight, closeTo(3000, 0.0001));
  });

  test('manual rect uses current scroll offset', () {
    const metrics = WebScrollMetrics(
      scrollX: 0,
      scrollY: 500,
      innerWidth: 200,
      innerHeight: 100,
      scrollWidth: 200,
      scrollHeight: 2000,
    );
    final bubble = overlayBubbleFromRect(
      left: 20,
      top: 10,
      width: 80,
      height: 40,
      metrics: metrics,
      translated: '框',
    );
    expect(bubble.source, OverlaySource.manual);
    expect(bubble.x, closeTo(0.1, 0.0001));
    expect(bubble.w, closeTo(0.4, 0.0001));
    expect(bubble.yPx, closeTo(510, 0.0001));
    expect(bubble.hPx, closeTo(40, 0.0001));
  });

  test('library json includes bookmarks and overlays', () {
    final page = OverlayPage(
      urlKey: 'https://a.example/ch/1',
      url: 'https://a.example/ch/1',
      pageWidth: 400,
      scrollHeight: 2000,
      updatedAt: DateTime.utc(2026, 9, 21),
      bubbles: [
        OverlayBubble(
          id: '1',
          source: OverlaySource.manual,
          original: 'hi',
          translated: '嗨',
          x: 0.2,
          yPx: 100,
          w: 0.4,
          hPx: 40,
        ),
      ],
    );
    final json = encodeLibraryJson(
      bookmarks: const [
        Bookmark(id: 'b1', name: '站A', url: 'https://a.example/ch/1'),
      ],
      overlays: {page.urlKey: page},
    );
    final decoded = decodeLibraryJson(json);
    expect(decoded.bookmarks.single.name, '站A');
    expect(decoded.overlayCount, 1);
    expect(decoded.bubbleCount, 1);
    expect(decoded.overlays[page.urlKey]!.bubbles.single.translated, '嗨');
  });

  test('library decoder accepts old bookmark-only json', () {
    final decoded = decodeLibraryJson(
      encodeBookmarksJson(const [
        Bookmark(id: '1', name: '舊', url: 'https://old.example'),
      ]),
    );
    expect(decoded.bookmarks.single.name, '舊');
    expect(decoded.overlays, isEmpty);
  });

  test('library decoder accepts overlay-only json', () {
    final page = OverlayPage(
      urlKey: 'https://a.example/ch/2',
      url: 'https://a.example/ch/2',
      pageWidth: 360,
      scrollHeight: 800,
      updatedAt: DateTime.utc(2026, 9, 21),
      bubbles: [
        OverlayBubble(
          id: 'x',
          source: OverlaySource.gemini,
          original: 'a',
          translated: '甲',
          x: 0.1,
          yPx: 10,
          w: 0.2,
          hPx: 20,
        ),
      ],
    );
    final decoded = decodeLibraryJson(encodeOverlayPagesJson({page.urlKey: page}));
    expect(decoded.bookmarks, isEmpty);
    expect(decoded.overlays[page.urlKey]!.bubbles.single.translated, '甲');
  });

  test('merge overlay pages keeps unique bubbles and updates same id', () {
    OverlayPage page({
      required String id,
      required String text,
      required DateTime updatedAt,
    }) {
      return OverlayPage(
        urlKey: 'https://a.example/ch',
        url: 'https://a.example/ch',
        pageWidth: 400,
        scrollHeight: 1000,
        updatedAt: updatedAt,
        bubbles: [
          OverlayBubble(
            id: id,
            source: OverlaySource.manual,
            original: '',
            translated: text,
            x: 0.1,
            yPx: 10,
            w: 0.2,
            hPx: 20,
          ),
        ],
      );
    }

    final merged = mergeOverlayPages(
      {
        'https://a.example/ch': page(
          id: 'keep',
          text: '舊框',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      },
      {
        'https://a.example/ch': OverlayPage(
          urlKey: 'https://a.example/ch',
          url: 'https://a.example/ch',
          pageWidth: 400,
          scrollHeight: 1200,
          updatedAt: DateTime.utc(2026, 9, 1),
          bubbles: [
            OverlayBubble(
              id: 'keep',
              source: OverlaySource.manual,
              original: '',
              translated: '新譯',
              x: 0.1,
              yPx: 10,
              w: 0.2,
              hPx: 20,
            ),
            OverlayBubble(
              id: 'new',
              source: OverlaySource.manual,
              original: '',
              translated: '新框',
              x: 0.4,
              yPx: 80,
              w: 0.2,
              hPx: 20,
            ),
          ],
        ),
      },
    );
    final bubbles = merged['https://a.example/ch']!.bubbles;
    expect(bubbles.map((b) => b.translated), containsAll(['新譯', '新框']));
    expect(merged['https://a.example/ch']!.scrollHeight, closeTo(1200, 0.001));
  });

  test('legacy gemini prefs still load after adding other providers', () async {
    SharedPreferences.setMockInitialValues({
      'gemini_api_key': 'old-gemini',
      'gemini_model': 'gemini-2.5-flash',
    });
    final store = SettingsStore();
    await store.load();
    expect(store.provider, AiProvider.gemini);
    expect(store.geminiApiKey, 'old-gemini');
    expect(store.geminiModel, 'gemini-2.5-flash');
    expect(store.openaiBaseUrl, SettingsStore.defaultOpenAiBaseUrl);
    expect(store.ollamaBaseUrl, SettingsStore.defaultOllamaBaseUrl);
    expect(store.missingRequiredFields, isEmpty);
  });

  test('openai and ollama each require their own fields', () {
    final openai = SettingsStore()..provider = AiProvider.openai;
    expect(openai.missingRequiredFields, ['OpenAI API Key', 'OpenAI 模型名稱']);

    final ollama = SettingsStore()
      ..provider = AiProvider.ollama
      ..ollamaModel = 'llava';
    expect(ollama.missingRequiredFields, isEmpty);
  });

  test('openai translator posts chat completions and parses bubbles', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(request.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o');
      expect(body['response_format'], {'type': 'json_object'});
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content':
                    '{"bubbles":[{"original":"hi","translated":"hello","x":0.1,"y":0.2,"w":0.3,"h":0.15}]}',
              },
            },
          ],
        }),
        200,
      );
    });
    final settings = SettingsStore()
      ..openaiApiKey = 'sk-test'
      ..openaiModel = 'gpt-4o';
    final bubbles = await OpenAiTranslator(client: client).translatePage(
      settings: settings,
      jpegBytes: Uint8List.fromList([0, 1, 2]),
      imageWidth: 1000,
      imageHeight: 2000,
    );
    expect(bubbles.single.translated, 'hello');
    expect(bubbles.single.x, closeTo(0.1, 0.0001));
  });

  test('ollama native chat posts images and parses json', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://127.0.0.1:11434/api/chat');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'llava');
      expect(body['stream'], false);
      expect(body['format'], 'json');
      final messages = body['messages'] as List;
      expect((messages.first as Map)['images'], isNotEmpty);
      return http.Response(
        jsonEncode({
          'message': {
            'content':
                '{"bubbles":[{"original":"a","translated":"A","x":0.2,"y":0.3,"w":0.4,"h":0.1}]}',
          },
        }),
        200,
      );
    });
    final settings = SettingsStore()
      ..provider = AiProvider.ollama
      ..ollamaModel = 'llava';
    final bubbles = await OllamaTranslator(client: client).translatePage(
      settings: settings,
      jpegBytes: Uint8List.fromList([0, 1, 2]),
      imageWidth: 500,
      imageHeight: 500,
    );
    expect(bubbles.single.translated, 'A');
  });

  test('ollama /v1 url uses openai compatible chat completions', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'http://192.168.1.8:11434/v1/chat/completions',
      );
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content':
                    '{"bubbles":[{"original":"b","translated":"B","x":0.1,"y":0.1,"w":0.2,"h":0.2}]}',
              },
            },
          ],
        }),
        200,
      );
    });
    final settings = SettingsStore()
      ..ollamaBaseUrl = 'http://192.168.1.8:11434/v1'
      ..ollamaModel = 'llava';
    final bubbles = await OllamaTranslator(client: client).translatePage(
      settings: settings,
      jpegBytes: Uint8List.fromList([9]),
      imageWidth: 100,
      imageHeight: 100,
    );
    expect(bubbles.single.translated, 'B');
  });

  test('translator factory returns the selected provider', () {
    expect(createTranslator(AiProvider.gemini), isA<GeminiTranslator>());
    expect(createTranslator(AiProvider.openai), isA<OpenAiTranslator>());
    expect(createTranslator(AiProvider.ollama), isA<OllamaTranslator>());
  });

  test('provider url helpers', () {
    expect(
      buildGeminiUri(
        'https://generativelanguage.googleapis.com/v1beta',
        'gemini-2.5-flash',
        'key',
      ).toString(),
      contains('/models/gemini-2.5-flash:generateContent'),
    );
    expect(
      buildOpenAiChatUri('https://api.openai.com/v1').toString(),
      'https://api.openai.com/v1/chat/completions',
    );
    expect(
      buildOllamaChatUri('http://127.0.0.1:11434').toString(),
      'http://127.0.0.1:11434/api/chat',
    );
    expect(isOpenAiCompatibleUrl('http://127.0.0.1:11434/v1'), isTrue);
    expect(isOpenAiCompatibleUrl('http://127.0.0.1:11434'), isFalse);
  });
}
