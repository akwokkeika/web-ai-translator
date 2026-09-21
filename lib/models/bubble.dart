class Bubble {
  Bubble({
    required this.original,
    required this.translated,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.vertical = false,
  });

  final String original;
  String translated;
  final double x;
  final double y;
  final double w;
  final double h;
  final bool vertical;

  Bubble copyWith({String? translated}) {
    return Bubble(
      original: original,
      translated: translated ?? this.translated,
      x: x,
      y: y,
      w: w,
      h: h,
      vertical: vertical,
    );
  }
}

class TranslationPage {
  const TranslationPage({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.bubbles,
  });

  final List<int> imageBytes;
  final int width;
  final int height;
  final List<Bubble> bubbles;
}
