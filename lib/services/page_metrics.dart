import 'dart:convert';

class WebScrollMetrics {
  const WebScrollMetrics({
    required this.scrollX,
    required this.scrollY,
    required this.innerWidth,
    required this.innerHeight,
    required this.scrollWidth,
    required this.scrollHeight,
    this.dpr = 1,
  });

  final double scrollX;
  final double scrollY;
  final double innerWidth;
  final double innerHeight;
  final double scrollWidth;
  final double scrollHeight;
  final double dpr;

  double get viewTop => scrollY;
  double get viewBottom => scrollY + innerHeight;

  bool get isUsable => innerWidth > 1 && innerHeight > 1;

  factory WebScrollMetrics.zero() => const WebScrollMetrics(
        scrollX: 0,
        scrollY: 0,
        innerWidth: 1,
        innerHeight: 1,
        scrollWidth: 1,
        scrollHeight: 1,
      );

  factory WebScrollMetrics.fromJson(Map<String, dynamic> json) {
    return WebScrollMetrics(
      scrollX: _asDouble(json['scrollX']),
      scrollY: _asDouble(json['scrollY']),
      innerWidth: _asDouble(json['innerWidth'], 1).clamp(1, 100000),
      innerHeight: _asDouble(json['innerHeight'], 1).clamp(1, 100000),
      scrollWidth: _asDouble(json['scrollWidth'], 1).clamp(1, 10000000),
      scrollHeight: _asDouble(json['scrollHeight'], 1).clamp(1, 10000000),
      dpr: _asDouble(json['dpr'], 1).clamp(0.5, 8),
    );
  }

  static WebScrollMetrics? tryParse(dynamic raw) {
    Map<String, dynamic>? map;
    if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } on FormatException {
        return null;
      }
    }
    if (map == null) return null;
    return WebScrollMetrics.fromJson(map);
  }
}

double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Injected into every page. Finds window or inner scroll root, then posts
/// metrics to Flutter on scroll/resize.
const pageMetricsScript = r'''
(function() {
  function collect() {
    var se = document.scrollingElement || document.documentElement;
    var best = se;
    var bestOverflow = se ? Math.max(0, se.scrollHeight - se.clientHeight) : 0;
    var nodes = document.querySelectorAll('div, main, section, article');
    var limit = Math.min(nodes.length, 240);
    for (var i = 0; i < limit; i++) {
      var el = nodes[i];
      var style = window.getComputedStyle(el);
      var oy = style.overflowY;
      if ((oy === 'auto' || oy === 'scroll' || oy === 'overlay') &&
          el.scrollHeight > el.clientHeight + 80) {
        var overflow = el.scrollHeight - el.clientHeight;
        if (overflow > bestOverflow) {
          bestOverflow = overflow;
          best = el;
        }
      }
    }
    var useWindow = !best || best === se || best === document.body ||
        best === document.documentElement;
    var scrollX = useWindow
      ? (window.scrollX || window.pageXOffset || 0)
      : (best.scrollLeft || 0);
    var scrollY = useWindow
      ? (window.scrollY || window.pageYOffset || 0)
      : (best.scrollTop || 0);
    var innerWidth = window.innerWidth || (se ? se.clientWidth : 1) || 1;
    var innerHeight = useWindow
      ? (window.innerHeight || (se ? se.clientHeight : 1) || 1)
      : (best.clientHeight || 1);
    var scrollWidth = Math.max(
      useWindow ? (se ? se.scrollWidth : 0) : (best.scrollWidth || 0),
      document.documentElement ? document.documentElement.scrollWidth : 0,
      document.body ? document.body.scrollWidth : 0,
      1
    );
    var scrollHeight = Math.max(
      useWindow ? (se ? se.scrollHeight : 0) : (best.scrollHeight || 0),
      document.documentElement ? document.documentElement.scrollHeight : 0,
      document.body ? document.body.scrollHeight : 0,
      1
    );
    return {
      scrollX: scrollX,
      scrollY: scrollY,
      innerWidth: innerWidth,
      innerHeight: innerHeight,
      scrollWidth: scrollWidth,
      scrollHeight: scrollHeight,
      dpr: window.devicePixelRatio || 1
    };
  }
  window.__aiMangaCollect = collect;
  function post() {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('pageMetrics', collect());
      }
    } catch (e) {}
  }
  if (!window.__aiMangaMetrics) {
    window.__aiMangaMetrics = true;
    window.addEventListener('scroll', post, true);
    window.addEventListener('resize', post, true);
    document.addEventListener('scroll', post, true);
    setInterval(post, 280);
  }
  post();
  return collect();
})();
''';
