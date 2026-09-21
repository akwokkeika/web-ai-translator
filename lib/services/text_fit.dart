import 'package:flutter/painting.dart';

/// Picks a font size that wraps first. Only goes below [minFontSize] if the
/// wrapped text still overflows the bubble.
double fitBubbleFontSize({
  required String text,
  required double maxWidth,
  required double maxHeight,
  required double minFontSize,
  double floorFontSize = 8,
  double height = 1.25,
  FontWeight fontWeight = FontWeight.w700,
}) {
  if (text.isEmpty || maxWidth <= 1 || maxHeight <= 1) {
    return minFontSize.clamp(floorFontSize, 512).toDouble();
  }

  final minSize = minFontSize.clamp(floorFontSize, 512).toDouble();
  final floor = floorFontSize.clamp(4, minSize).toDouble();

  bool fits(double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          height: height,
          fontWeight: fontWeight,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.height <= maxHeight + 0.5;
  }

  double largestFit(double lo, double hi) {
    if (!fits(lo)) return lo;
    var low = lo;
    var high = hi;
    for (var i = 0; i < 14; i++) {
      final mid = (low + high) / 2;
      if (fits(mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  if (fits(minSize)) {
    return minSize;
  }
  return largestFit(floor, minSize);
}
