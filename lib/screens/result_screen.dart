import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/bubble.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/bubble_text.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.page,
    required this.settings,
  });

  final TranslationPage page;
  final SettingsStore settings;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late List<Bubble> _bubbles;
  bool _showOriginal = false;
  final _transform = TransformationController();
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
    _bubbles = [
      for (final b in widget.page.bubbles)
        Bubble(
          original: b.original,
          translated: b.translated,
          x: b.x,
          y: b.y,
          w: b.w,
          h: b.h,
          vertical: b.vertical,
        ),
    ];
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _transform.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  Future<void> _nudgeFont(int delta) {
    return widget.settings.setMinFontPx(widget.settings.minFontPx + delta);
  }

  Future<void> _editBubble(int index) async {
    final bubble = _bubbles[index];
    final controller = TextEditingController(text: bubble.translated);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('編輯譯文'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bubble.original.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    bubble.original,
                    style: const TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                ),
              TextField(
                controller: controller,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(hintText: '譯文'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('隱藏'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return;
    setState(() {
      if (result.trim().isEmpty) {
        _bubbles.removeAt(index);
      } else {
        _bubbles[index].translated = result.trim();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = Uint8List.fromList(widget.page.imageBytes);
    final pageW = widget.page.width.toDouble();
    final pageH = widget.page.height.toDouble();
    final minFontPx = widget.settings.minFontPx;

    return Scaffold(
      appBar: AppBar(
        title: Text('翻譯結果（${_bubbles.length} 框）'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _showOriginal = !_showOriginal),
            child: Text(_showOriginal ? '顯示譯文' : '顯示原文'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!_fitted && constraints.maxWidth > 0) {
                  _fitted = true;
                  final scale = constraints.maxWidth / pageW;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _transform.value = Matrix4.identity()
                      ..scaleByDouble(scale, scale, scale, 1);
                  });
                }
                final viewScale = constraints.maxWidth <= 0
                    ? 1.0
                    : constraints.maxWidth / pageW;
                final minImageFont = minFontPx / viewScale;
                return ColoredBox(
                  color: Colors.black,
                  child: InteractiveViewer(
                    transformationController: _transform,
                    constrained: false,
                    minScale: 0.2,
                    maxScale: 5,
                    child: SizedBox(
                      width: pageW,
                      height: pageH,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            bytes,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                          ),
                          for (var i = 0; i < _bubbles.length; i++)
                            Positioned(
                              left: _bubbles[i].x * pageW,
                              top: _bubbles[i].y * pageH,
                              width: (_bubbles[i].w * pageW).clamp(28, pageW),
                              height: (_bubbles[i].h * pageH).clamp(22, pageH),
                              child: Material(
                                color: AppColors.paper.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: () => _editBubble(i),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: BubbleText(
                                      text: _showOriginal
                                          ? _bubbles[i].original
                                          : _bubbles[i].translated,
                                      minFontSize: minImageFont,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '縮小字級',
                    onPressed: minFontPx <= SettingsStore.minFontPxFloor
                        ? null
                        : () => _nudgeFont(-1),
                    icon: const Icon(Icons.text_decrease),
                  ),
                  Text(
                    '${minFontPx}px',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    tooltip: '放大字級',
                    onPressed: minFontPx >= SettingsStore.minFontPxCeil
                        ? null
                        : () => _nudgeFont(1),
                    icon: const Icon(Icons.text_increase),
                  ),
                  Expanded(
                    child: Text(
                      _bubbles.isEmpty
                          ? '沒有偵測到對白。可返回再截一次。'
                          : '最小字級；換行後仍塞不下才縮小。點氣泡可改譯文。',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
