import 'dart:math';

import '../models/bubble.dart';
import '../models/overlay_page.dart';
import 'page_metrics.dart';

String overlayUrlKey(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return text;
  final noHash = uri
      .replace(fragment: '')
      .toString()
      .replaceFirst(RegExp(r'#.*$'), '');
  return noHash.replaceFirst(RegExp(r'/+$'), '');
}

String newOverlayId() {
  final rand = Random();
  return '${DateTime.now().microsecondsSinceEpoch}-${rand.nextInt(1 << 32)}';
}

List<OverlayBubble> overlayBubblesFromScreenshot({
  required List<Bubble> bubbles,
  required WebScrollMetrics metrics,
  OverlaySource source = OverlaySource.gemini,
}) {
  if (!metrics.isUsable) return const [];
  return [
    for (final bubble in bubbles)
      OverlayBubble(
        id: newOverlayId(),
        source: source,
        original: bubble.original,
        translated: bubble.translated,
        x: bubble.x.clamp(0.0, 1.0),
        yPx: metrics.scrollY + bubble.y * metrics.innerHeight,
        w: bubble.w.clamp(0.01, 1.0),
        hPx: (bubble.h * metrics.innerHeight).clamp(18, metrics.innerHeight),
        vertical: bubble.vertical,
      ),
  ];
}

List<OverlayBubble> mergeGeminiCapture({
  required List<OverlayBubble> current,
  required List<OverlayBubble> captured,
  required double viewTop,
  required double viewBottom,
}) {
  final kept = [
    for (final bubble in current)
      if (bubble.source != OverlaySource.gemini ||
          !_centerInView(bubble, viewTop, viewBottom))
        bubble,
  ];
  return [...kept, ...captured];
}

bool _centerInView(OverlayBubble bubble, double viewTop, double viewBottom) {
  final center = bubble.yPx + bubble.hPx / 2;
  return center >= viewTop - 8 && center <= viewBottom + 8;
}

OverlayBubble overlayBubbleFromRect({
  required double left,
  required double top,
  required double width,
  required double height,
  required WebScrollMetrics metrics,
  String translated = '',
  String original = '',
}) {
  final innerW = metrics.innerWidth <= 0 ? 1.0 : metrics.innerWidth;
  final x = (left / innerW).clamp(0.0, 1.0);
  final w = (width / innerW).clamp(0.02, 1.0 - x);
  return OverlayBubble(
    id: newOverlayId(),
    source: OverlaySource.manual,
    original: original,
    translated: translated,
    x: x,
    yPx: metrics.scrollY + top,
    w: w,
    hPx: height.clamp(22, 4000),
  );
}
