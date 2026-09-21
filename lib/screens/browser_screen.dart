import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/bubble.dart';
import '../models/overlay_page.dart';
import '../services/bookmark_store.dart';
import '../services/image_prep.dart';
import '../services/overlay_coords.dart';
import '../services/overlay_store.dart';
import '../services/page_metrics.dart';
import '../services/settings_store.dart';
import '../services/translator_factory.dart';
import '../theme.dart';
import '../widgets/page_overlay.dart';
import 'bookmarks_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

const _homeHtml = '''
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      margin: 0;
      background: #12100e;
      color: #f4efe6;
      font-family: sans-serif;
      padding: 28px 20px;
    }
    h1 { font-size: 26px; margin: 0 0 8px; }
    p { color: #b9a992; line-height: 1.7; }
    .card {
      background: #2a241f;
      border-radius: 14px;
      padding: 14px 16px;
      margin-top: 12px;
      line-height: 1.55;
    }
    .stamp { color: #c23a2b; font-weight: 700; }
  </style>
</head>
<body>
  <h1>瀏覽器翻譯</h1>
  <p>在上方貼上網址。畫面出現後，按底部「翻譯本頁」。譯文會疊在網頁 overlay，可手動加框並自動保存。</p>
  <div class="card"><span class="stamp">1.</span> 先到設定選擇 Gemini、OpenAI 或本機 Ollama</div>
  <div class="card"><span class="stamp">2.</span> 打開要翻譯的網頁，等內容載入完成</div>
  <div class="card"><span class="stamp">3.</span> 翻譯或手動畫框，overlay 會跟著頁面捲動</div>
</body>
</html>
''';

const _desktopUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.settings,
    required this.bookmarks,
    required this.overlays,
  });

  final SettingsStore settings;
  final BookmarkStore bookmarks;
  final OverlayStore overlays;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  InAppWebViewController? _controller;
  final _url = TextEditingController();
  final _urlFocus = FocusNode();
  double _progress = 0;
  bool _canBack = false;
  bool _canForward = false;
  bool _desktop = false;
  bool _busy = false;
  bool _overlayOn = false;
  bool _overlayEditing = false;
  bool _showOriginal = false;
  bool _editHintShown = false;
  String _overlayKey = '';
  WebScrollMetrics _metrics = WebScrollMetrics.zero();
  List<OverlayBubble> _bubbles = [];
  TranslationPage? _lastPage;

  @override
  void dispose() {
    _url.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  String _normalizeInput(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return text;
    if (text.startsWith('http://') || text.startsWith('https://')) return text;
    if (text.contains(' ') || !text.contains('.')) {
      return 'https://www.google.com/search?q=${Uri.encodeComponent(text)}';
    }
    return 'https://$text';
  }

  Future<void> _submitUrl() async {
    final target = _normalizeInput(_url.text);
    if (target.isEmpty) return;
    _urlFocus.unfocus();
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  Future<void> _syncNav() async {
    final controller = _controller;
    if (controller == null) return;
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canBack = back;
      _canForward = forward;
    });
  }

  void _onUrl(WebUri? uri) {
    if (uri == null || _urlFocus.hasFocus) return;
    final value = uri.toString();
    if (value.startsWith('data:') || value == 'about:blank') {
      _url.text = '';
      return;
    }
    _url.text = value;
  }

  Future<void> _toggleDesktop() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _desktop = !_desktop);
    await controller.setSettings(
      settings: InAppWebViewSettings(
        userAgent: _desktop ? _desktopUa : null,
        preferredContentMode: _desktop
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.MOBILE,
        useWideViewPort: true,
      ),
    );
    await controller.reload();
  }

  void _onMetrics(WebScrollMetrics next) {
    if (!mounted) return;
    final prev = _metrics;
    final unchanged = (prev.scrollY - next.scrollY).abs() < 0.5 &&
        (prev.scrollX - next.scrollX).abs() < 0.5 &&
        (prev.innerWidth - next.innerWidth).abs() < 0.5 &&
        (prev.innerHeight - next.innerHeight).abs() < 0.5 &&
        (prev.scrollHeight - next.scrollHeight).abs() < 1;
    if (unchanged) return;
    if (_overlayOn) {
      setState(() => _metrics = next);
    } else {
      _metrics = next;
    }
  }

  Future<WebScrollMetrics> _readMetrics() async {
    final controller = _controller;
    if (controller == null) return _metrics;
    try {
      await controller.evaluateJavascript(source: pageMetricsScript);
      final raw = await controller.evaluateJavascript(
        source:
            r'(function(){var c=window.__aiMangaCollect&&window.__aiMangaCollect();return typeof c==="string"?c:JSON.stringify(c||{});})()',
      );
      final parsed = WebScrollMetrics.tryParse(raw);
      if (parsed != null) {
        _metrics = parsed;
        return parsed;
      }
    } catch (_) {}
    return _metrics;
  }

  Future<void> _syncOverlayForUrl(WebUri? uri) async {
    final url = uri?.toString() ?? _currentHttpUrl() ?? '';
    if (url.startsWith('data:') || url == 'about:blank') {
      if (_overlayKey.isEmpty && _bubbles.isEmpty) return;
      setState(() {
        _overlayKey = '';
        _bubbles = [];
        _overlayEditing = false;
      });
      return;
    }
    final key = overlayUrlKey(url);
    if (key.isEmpty || key == _overlayKey) return;
    final page = widget.overlays.getByUrl(url);
    setState(() {
      _overlayKey = key;
      _bubbles = page == null
          ? <OverlayBubble>[]
          : [for (final bubble in page.bubbles) bubble.copyWith()];
      _overlayEditing = false;
      if (_bubbles.isNotEmpty) _overlayOn = true;
    });
  }

  Future<void> _persistOverlay() async {
    final url = _currentHttpUrl();
    if (url == null) return;
    await widget.overlays.savePage(
      url: url,
      bubbles: _bubbles,
      pageWidth: _metrics.innerWidth,
      scrollHeight: _metrics.scrollHeight,
    );
    _overlayKey = overlayUrlKey(url);
  }

  void _onOverlayChanged(List<OverlayBubble> next) {
    setState(() => _bubbles = next);
    _persistOverlay();
  }

  void _nudgeOverlay(double dy) {
    if (_bubbles.isEmpty) return;
    setState(() {
      _bubbles = [
        for (final bubble in _bubbles) bubble.copyWith(yPx: bubble.yPx + dy),
      ];
    });
    _persistOverlay();
  }

  Future<void> _clearOverlay() async {
    if (_bubbles.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除 overlay'),
        content: const Text('會刪除本頁已保存的文字框和譯文。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _bubbles = [];
      _overlayEditing = false;
    });
    final url = _currentHttpUrl();
    if (url != null) await widget.overlays.remove(url);
  }

  void _toggleOverlay() {
    setState(() {
      _overlayOn = !_overlayOn;
      if (!_overlayOn) _overlayEditing = false;
    });
  }

  void _toggleEditing() {
    final next = !_overlayEditing;
    setState(() {
      _overlayOn = true;
      _overlayEditing = next;
    });
    if (next && !_editHintShown && mounted) {
      _editHintShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('拖曳空白處新增文字框，點選後拖角落可改大小')),
      );
    }
  }

  Future<void> _openLastScreenshot() async {
    final page = _lastPage;
    if (page == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(page: page, settings: widget.settings),
      ),
    );
  }

  Future<void> _translate() async {
    if (_busy) return;
    final missingFields = widget.settings.missingRequiredFields;
    if (missingFields.isNotEmpty) {
      final missing = missingFields.join('、');
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('尚未完成設定'),
          content: Text('請先到設定頁填入 $missing。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('前往設定'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SettingsScreen(settings: widget.settings),
          ),
        );
      }
      return;
    }

    final controller = _controller;
    if (controller == null) return;

    final screenshot = await controller.takeScreenshot(
      screenshotConfiguration: ScreenshotConfiguration(
        compressFormat: CompressFormat.JPEG,
        quality: 85,
      ),
    );
    if (screenshot == null || screenshot.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('截圖失敗，請等頁面載入完成後再試')),
      );
      return;
    }

    setState(() => _busy = true);
    final status = ValueNotifier('正在處理截圖…');
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (context, value, _) {
                return Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 16),
                    Expanded(child: Text(value)),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    try {
      final metrics = await _readMetrics();
      final prepared = prepareScreenshot(screenshot);
      status.value = '正在請 ${widget.settings.provider.label} 翻譯…';
      final bubbles = await createTranslator(widget.settings.provider).translatePage(
        settings: widget.settings,
        jpegBytes: prepared.uploadBytes,
        imageWidth: prepared.width,
        imageHeight: prepared.height,
      );
      if (!mounted) return;
      final captured = overlayBubblesFromScreenshot(
        bubbles: bubbles,
        metrics: metrics,
      );
      final merged = mergeGeminiCapture(
        current: _bubbles,
        captured: captured,
        viewTop: metrics.viewTop,
        viewBottom: metrics.viewBottom,
      );
      _lastPage = TranslationPage(
        imageBytes: prepared.originalBytes,
        width: prepared.width,
        height: prepared.height,
        bubbles: bubbles,
      );
      setState(() {
        _metrics = metrics;
        _bubbles = merged;
        _overlayOn = true;
        _overlayEditing = false;
      });
      await _persistOverlay();
      if (!mounted) return;
      Navigator.pop(context);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('已疊上 ${captured.length} 個文字框'),
          action: SnackBarAction(
            label: '查看截圖',
            onPressed: _openLastScreenshot,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      status.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
  }

  String? _currentHttpUrl() {
    final text = _url.text.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      return text;
    }
    return null;
  }

  Future<void> _addBookmark() async {
    final current = _currentHttpUrl() ?? '';
    String title = '';
    try {
      title = (await _controller?.getTitle())?.trim() ?? '';
    } catch (_) {}
    if (!mounted) return;
    final name = TextEditingController(
      text: title.isEmpty ? _guessName(current) : title,
    );
    final url = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('加入書籤'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '名稱',
                  hintText: '自訂名稱',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '網址',
                  hintText: 'https://',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
    final savedName = name.text;
    final savedUrl = url.text.trim();
    name.dispose();
    url.dispose();
    if (ok != true) return;
    if (savedUrl.isEmpty ||
        !(savedUrl.startsWith('http://') || savedUrl.startsWith('https://'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入有效網址')),
      );
      return;
    }
    await widget.bookmarks.add(name: savedName, url: savedUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入書籤')),
    );
  }

  String _guessName(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : url;
  }

  Future<void> _openBookmarks() async {
    final url = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BookmarksScreen(
          store: widget.bookmarks,
          overlays: widget.overlays,
        ),
      ),
    );
    _overlayKey = '';
    if (url != null && url.isNotEmpty) {
      _url.text = url;
      await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      return;
    }
    final current = _currentHttpUrl();
    if (current == null) return;
    await _syncOverlayForUrl(WebUri(current));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _controller?.goBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                url: _url,
                focus: _urlFocus,
                desktop: _desktop,
                onSubmit: _submitUrl,
                onReload: () => _controller?.reload(),
                onSettings: _openSettings,
                onToggleDesktop: _toggleDesktop,
                onBookmarks: _openBookmarks,
                onAddBookmark: _addBookmark,
              ),
              if (_progress > 0 && _progress < 1)
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 2,
                  color: AppColors.stamp,
                  backgroundColor: AppColors.panel,
                ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InAppWebView(
                      initialData: InAppWebViewInitialData(
                        data: _homeHtml,
                        mimeType: 'text/html',
                        encoding: 'utf-8',
                      ),
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        UserScript(
                          source: pageMetricsScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_END,
                          forMainFrameOnly: true,
                        ),
                      ]),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        supportZoom: true,
                        builtInZoomControls: true,
                        displayZoomControls: false,
                        useWideViewPort: true,
                        loadWithOverviewMode: true,
                        mixedContentMode:
                            MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                        thirdPartyCookiesEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        hardwareAcceleration: true,
                        allowsInlineMediaPlayback: true,
                        useHybridComposition: true,
                        verticalScrollBarEnabled: true,
                        horizontalScrollBarEnabled: true,
                      ),
                      onWebViewCreated: (controller) async {
                        _controller = controller;
                        controller.addJavaScriptHandler(
                          handlerName: 'pageMetrics',
                          callback: (args) {
                            final parsed = WebScrollMetrics.tryParse(
                              args.isNotEmpty ? args.first : null,
                            );
                            if (parsed != null) _onMetrics(parsed);
                            return null;
                          },
                        );
                        if (Platform.isAndroid) {
                          await InAppWebViewController
                              .setWebContentsDebuggingEnabled(true);
                        }
                      },
                      onLoadStart: (controller, uri) {
                        _onUrl(uri);
                        _syncNav();
                      },
                      onLoadStop: (controller, uri) async {
                        _onUrl(uri);
                        _syncNav();
                        await _syncOverlayForUrl(uri);
                        await controller.evaluateJavascript(
                          source: pageMetricsScript,
                        );
                        if (mounted) setState(() => _progress = 1);
                      },
                      onProgressChanged: (controller, progress) {
                        setState(() => _progress = progress / 100);
                      },
                      onUpdateVisitedHistory: (controller, uri, _) {
                        _onUrl(uri);
                        _syncNav();
                        _syncOverlayForUrl(uri);
                      },
                      onReceivedError: (controller, request, error) {
                        debugPrint('WebView error: ${error.description}');
                      },
                    ),
                    if (_overlayOn)
                      ListenableBuilder(
                        listenable: widget.settings,
                        builder: (context, _) {
                          return PageOverlayLayer(
                            bubbles: _bubbles,
                            metrics: _metrics,
                            editing: _overlayEditing,
                            minFontPx: widget.settings.minFontPx.toDouble(),
                            showOriginal: _showOriginal,
                            onChanged: _onOverlayChanged,
                          );
                        },
                      ),
                  ],
                ),
              ),
              OverlayToolbar(
                enabled: _overlayOn,
                editing: _overlayEditing,
                busy: _busy,
                count: _bubbles.length,
                showOriginal: _showOriginal,
                onToggleEnabled: _toggleOverlay,
                onToggleEditing: _toggleEditing,
                onToggleOriginal: () {
                  setState(() => _showOriginal = !_showOriginal);
                },
                onNudge: _nudgeOverlay,
                onClear: _clearOverlay,
              ),
              _BottomBar(
                canBack: _canBack,
                canForward: _canForward,
                busy: _busy,
                onBack: () => _controller?.goBack(),
                onForward: () => _controller?.goForward(),
                onHome: () => _controller?.loadData(data: _homeHtml),
                onBookmarks: _openBookmarks,
                onTranslate: _translate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.url,
    required this.focus,
    required this.desktop,
    required this.onSubmit,
    required this.onReload,
    required this.onSettings,
    required this.onToggleDesktop,
    required this.onBookmarks,
    required this.onAddBookmark,
  });

  final TextEditingController url;
  final FocusNode focus;
  final bool desktop;
  final VoidCallback onSubmit;
  final VoidCallback onReload;
  final VoidCallback onSettings;
  final VoidCallback onToggleDesktop;
  final VoidCallback onBookmarks;
  final VoidCallback onAddBookmark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.wood,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: url,
                focusNode: focus,
                textInputAction: TextInputAction.go,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  hintText: '貼上網址或搜尋',
                  prefixIcon: Icon(Icons.public, size: 18, color: AppColors.muted),
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              onPressed: onSubmit,
              icon: const Icon(Icons.arrow_forward),
              tooltip: '前往',
            ),
            IconButton(
              onPressed: onAddBookmark,
              icon: const Icon(Icons.star_border),
              tooltip: '加入書籤',
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'reload':
                    onReload();
                  case 'desktop':
                    onToggleDesktop();
                  case 'bookmarks':
                    onBookmarks();
                  case 'settings':
                    onSettings();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'reload', child: Text('重新整理')),
                PopupMenuItem(
                  value: 'desktop',
                  child: Text(desktop ? '使用手機版網站' : '使用桌面版網站'),
                ),
                const PopupMenuItem(value: 'bookmarks', child: Text('書籤')),
                const PopupMenuItem(value: 'settings', child: Text('模型設定')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.canBack,
    required this.canForward,
    required this.busy,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onBookmarks,
    required this.onTranslate,
  });

  final bool canBack;
  final bool canForward;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onHome;
  final VoidCallback onBookmarks;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.wood,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: canBack ? onBack : null,
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            ),
            IconButton(
              onPressed: canForward ? onForward : null,
              icon: const Icon(Icons.arrow_forward_ios, size: 18),
            ),
            IconButton(
              onPressed: onHome,
              icon: const Icon(Icons.home_outlined),
            ),
            IconButton(
              onPressed: onBookmarks,
              icon: const Icon(Icons.bookmarks_outlined),
              tooltip: '書籤',
            ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.stamp,
                foregroundColor: AppColors.paper,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: busy ? null : onTranslate,
              icon: const Icon(Icons.translate),
              label: Text(busy ? '翻譯中…' : '翻譯本頁'),
            ),
          ],
        ),
      ),
    );
  }
}
