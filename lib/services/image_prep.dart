import 'dart:typed_data';

import 'package:image/image.dart' as img;

class PreparedImage {
  const PreparedImage({
    required this.originalBytes,
    required this.uploadBytes,
    required this.width,
    required this.height,
  });

  final Uint8List originalBytes;
  final Uint8List uploadBytes;
  final int width;
  final int height;
}

PreparedImage prepareScreenshot(Uint8List bytes, {int maxWidth = 1400}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('無法解讀截圖');
  }

  img.Image work = decoded;
  if (work.width > maxWidth) {
    work = img.copyResize(work, width: maxWidth);
  }
  final jpeg = Uint8List.fromList(img.encodeJpg(work, quality: 78));
  return PreparedImage(
    originalBytes: bytes,
    uploadBytes: jpeg,
    width: decoded.width,
    height: decoded.height,
  );
}
