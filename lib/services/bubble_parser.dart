import '../models/bubble.dart';

double _toRatio(num value, int size) {
  final d = value.toDouble();
  if (size <= 0) return d.clamp(0, 1);
  final ratio = d.abs() <= 1.5 ? d : d / size;
  return ratio.clamp(0.0, 1.0);
}

double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String extractJsonObject(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    return trimmed;
  }
  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start >= 0 && end > start) {
    return trimmed.substring(start, end + 1);
  }
  throw const FormatException('模型沒有回傳 JSON');
}

List<Bubble> parseBubbles(
  Map<String, dynamic> json, {
  required int imageWidth,
  required int imageHeight,
}) {
  final raw = json['bubbles'];
  if (raw is! List) return const [];

  final bubbles = <Bubble>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    var x = _toRatio(_asDouble(map['x']), imageWidth);
    var y = _toRatio(_asDouble(map['y']), imageHeight);
    var w = _toRatio(_asDouble(map['w'] ?? map['width']), imageWidth);
    var h = _toRatio(_asDouble(map['h'] ?? map['height']), imageHeight);
    if (w <= 0.01 || h <= 0.01) continue;
    if (x + w > 1) w = (1 - x).clamp(0.01, 1);
    if (y + h > 1) h = (1 - y).clamp(0.01, 1);

    final original = '${map['original'] ?? map['source'] ?? ''}'.trim();
    final translated = '${map['translated'] ?? map['text'] ?? ''}'.trim();
    if (original.isEmpty && translated.isEmpty) continue;

    bubbles.add(
      Bubble(
        original: original,
        translated: translated.isEmpty ? original : translated,
        x: x,
        y: y,
        w: w,
        h: h,
        vertical: map['vertical'] == true,
      ),
    );
  }
  return bubbles;
}
