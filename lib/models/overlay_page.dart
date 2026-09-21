enum OverlaySource { gemini, manual }

OverlaySource overlaySourceFrom(String? raw) {
  return raw == OverlaySource.gemini.name
      ? OverlaySource.gemini
      : OverlaySource.manual;
}

class OverlayBubble {
  OverlayBubble({
    required this.id,
    required this.source,
    required this.original,
    required this.translated,
    required this.x,
    required this.yPx,
    required this.w,
    required this.hPx,
    this.vertical = false,
  });

  final String id;
  final OverlaySource source;
  final String original;
  String translated;
  double x;
  double yPx;
  double w;
  double hPx;
  final bool vertical;

  OverlayBubble copyWith({
    String? id,
    OverlaySource? source,
    String? original,
    String? translated,
    double? x,
    double? yPx,
    double? w,
    double? hPx,
    bool? vertical,
  }) {
    return OverlayBubble(
      id: id ?? this.id,
      source: source ?? this.source,
      original: original ?? this.original,
      translated: translated ?? this.translated,
      x: x ?? this.x,
      yPx: yPx ?? this.yPx,
      w: w ?? this.w,
      hPx: hPx ?? this.hPx,
      vertical: vertical ?? this.vertical,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'original': original,
        'translated': translated,
        'x': x,
        'yPx': yPx,
        'w': w,
        'hPx': hPx,
        'vertical': vertical,
      };

  factory OverlayBubble.fromJson(Map<String, dynamic> json) {
    return OverlayBubble(
      id: '${json['id'] ?? ''}',
      source: overlaySourceFrom(json['source']?.toString()),
      original: '${json['original'] ?? ''}',
      translated: '${json['translated'] ?? json['text'] ?? ''}',
      x: _asDouble(json['x']),
      yPx: _asDouble(json['yPx'] ?? json['y']),
      w: _asDouble(json['w'] ?? json['width']),
      hPx: _asDouble(json['hPx'] ?? json['h'] ?? json['height']),
      vertical: json['vertical'] == true,
    );
  }
}

class OverlayPage {
  const OverlayPage({
    required this.urlKey,
    required this.url,
    required this.pageWidth,
    required this.scrollHeight,
    required this.bubbles,
    required this.updatedAt,
  });

  final String urlKey;
  final String url;
  final double pageWidth;
  final double scrollHeight;
  final List<OverlayBubble> bubbles;
  final DateTime updatedAt;

  OverlayPage copyWith({
    String? urlKey,
    String? url,
    double? pageWidth,
    double? scrollHeight,
    List<OverlayBubble>? bubbles,
    DateTime? updatedAt,
  }) {
    return OverlayPage(
      urlKey: urlKey ?? this.urlKey,
      url: url ?? this.url,
      pageWidth: pageWidth ?? this.pageWidth,
      scrollHeight: scrollHeight ?? this.scrollHeight,
      bubbles: bubbles ?? this.bubbles,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'urlKey': urlKey,
        'url': url,
        'pageWidth': pageWidth,
        'scrollHeight': scrollHeight,
        'updatedAt': updatedAt.toIso8601String(),
        'bubbles': [for (final bubble in bubbles) bubble.toJson()],
      };

  factory OverlayPage.fromJson(Map<String, dynamic> json) {
    final raw = json['bubbles'];
    return OverlayPage(
      urlKey: '${json['urlKey'] ?? json['key'] ?? ''}',
      url: '${json['url'] ?? ''}',
      pageWidth: _asDouble(json['pageWidth'], 1),
      scrollHeight: _asDouble(json['scrollHeight']),
      updatedAt:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      bubbles: [
        if (raw is List)
          for (final item in raw)
            if (item is Map)
              OverlayBubble.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}

double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
