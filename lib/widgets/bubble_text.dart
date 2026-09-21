import 'package:flutter/material.dart';

import '../services/text_fit.dart';
import '../theme.dart';

class BubbleText extends StatelessWidget {
  const BubbleText({
    super.key,
    required this.text,
    required this.minFontSize,
  });

  final String text;
  final double minFontSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = fitBubbleFontSize(
          text: text,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          minFontSize: minFontSize,
        );
        return Align(
          alignment: Alignment.center,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: fontSize,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}
