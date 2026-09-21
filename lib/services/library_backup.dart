import 'dart:convert';

import '../models/bookmark.dart';
import '../models/overlay_page.dart';
import 'bookmark_store.dart';
import 'overlay_store.dart';

class LibraryBackup {
  const LibraryBackup({
    required this.bookmarks,
    required this.overlays,
  });

  final List<Bookmark> bookmarks;
  final Map<String, OverlayPage> overlays;

  int get overlayCount => overlays.length;
  int get bubbleCount => overlays.values.fold<int>(
        0,
        (sum, page) => sum + page.bubbles.length,
      );

  bool get isEmpty => bookmarks.isEmpty && overlays.isEmpty;
}

String encodeLibraryJson({
  required List<Bookmark> bookmarks,
  required Map<String, OverlayPage> overlays,
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'version': 2,
    'kind': 'ai-manga-library',
    'bookmarks': [for (final item in bookmarks) item.toJson()],
    'overlays': jsonDecode(encodeOverlayPagesJson(overlays)),
  });
}

LibraryBackup decodeLibraryJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is List) {
    return LibraryBackup(
      bookmarks: decodeBookmarksJson(raw),
      overlays: const {},
    );
  }
  if (decoded is! Map) {
    throw const FormatException('JSON 格式不正確');
  }
  final map = Map<String, dynamic>.from(decoded);
  final bookmarks = map.containsKey('bookmarks')
      ? decodeBookmarksJson(
          jsonEncode({'bookmarks': map['bookmarks']}),
        )
      : <Bookmark>[];
  final overlays = _decodeOverlays(map);
  if (bookmarks.isEmpty && overlays.isEmpty) {
    throw const FormatException('檔案裡沒有書籤或 overlay');
  }
  return LibraryBackup(bookmarks: bookmarks, overlays: overlays);
}

Map<String, OverlayPage> _decodeOverlays(Map<String, dynamic> map) {
  final overlaysRaw = map['overlays'];
  if (overlaysRaw is Map) {
    final nested = Map<String, dynamic>.from(overlaysRaw);
    if (nested['pages'] is Map) {
      return decodeOverlayPagesJson(jsonEncode(nested));
    }
    return decodeOverlayPagesJson(jsonEncode({'pages': nested}));
  }
  if (map['pages'] is Map) {
    return decodeOverlayPagesJson(jsonEncode(map));
  }
  return {};
}

String overlayPageTitle(OverlayPage page) {
  final url = page.url.isNotEmpty ? page.url : page.urlKey;
  final uri = Uri.tryParse(url);
  if (uri != null && uri.host.isNotEmpty) {
    final path = uri.path.isEmpty || uri.path == '/' ? '' : uri.path;
    return '${uri.host}$path';
  }
  return url.isEmpty ? 'Overlay 存檔' : url;
}
