import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/overlay_page.dart';
import 'overlay_coords.dart';

const overlayStoreKey = 'overlay_pages_v1';

String encodeOverlayPagesJson(Map<String, OverlayPage> pages) {
  return const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'pages': {
      for (final entry in pages.entries) entry.key: entry.value.toJson(),
    },
  });
}

Map<String, OverlayPage> decodeOverlayPagesJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('overlay JSON 格式不正確');
  }
  final pagesRaw = decoded['pages'];
  if (pagesRaw is! Map) return {};
  final pages = <String, OverlayPage>{};
  for (final entry in pagesRaw.entries) {
    if (entry.value is! Map) continue;
    final page = OverlayPage.fromJson(
      Map<String, dynamic>.from(entry.value as Map),
    );
    final key = page.urlKey.isEmpty ? '${entry.key}' : page.urlKey;
    if (key.isEmpty) continue;
    pages[key] = page.copyWith(urlKey: key);
  }
  return pages;
}

Map<String, OverlayPage> mergeOverlayPages(
  Map<String, OverlayPage> current,
  Map<String, OverlayPage> incoming,
) {
  final merged = Map<String, OverlayPage>.from(current);
  for (final entry in incoming.entries) {
    final key = overlayUrlKey(entry.key);
    if (key.isEmpty) continue;
    final page = entry.value.copyWith(urlKey: key);
    final existing = merged[key];
    merged[key] = existing == null ? page : _mergeOverlayPage(existing, page);
  }
  return merged;
}

OverlayPage _mergeOverlayPage(OverlayPage current, OverlayPage incoming) {
  final byId = <String, OverlayBubble>{
    for (final bubble in current.bubbles)
      if (bubble.id.isNotEmpty) bubble.id: bubble.copyWith(),
  };
  for (final bubble in incoming.bubbles) {
    final id = bubble.id.isEmpty ? newOverlayId() : bubble.id;
    byId[id] = bubble.copyWith(id: id);
  }
  final newer =
      incoming.updatedAt.isAfter(current.updatedAt) ? incoming : current;
  return newer.copyWith(
    url: incoming.url.isNotEmpty ? incoming.url : current.url,
    pageWidth: incoming.pageWidth > 1 ? incoming.pageWidth : current.pageWidth,
    scrollHeight: incoming.scrollHeight > current.scrollHeight
        ? incoming.scrollHeight
        : current.scrollHeight,
    bubbles: byId.values.toList(),
    updatedAt: newer.updatedAt,
  );
}

class OverlayStore extends ChangeNotifier {
  Map<String, OverlayPage> pages = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(overlayStoreKey);
    if (raw == null || raw.trim().isEmpty) {
      pages = {};
    } else {
      try {
        pages = decodeOverlayPagesJson(raw);
      } on FormatException {
        pages = {};
      }
    }
    notifyListeners();
  }

  OverlayPage? getByUrl(String url) {
    final key = overlayUrlKey(url);
    if (key.isEmpty) return null;
    return pages[key];
  }

  Future<void> savePage({
    required String url,
    required List<OverlayBubble> bubbles,
    required double pageWidth,
    required double scrollHeight,
  }) async {
    final key = overlayUrlKey(url);
    if (key.isEmpty) return;
    if (bubbles.isEmpty) {
      await remove(key);
      return;
    }
    pages = {
      ...pages,
      key: OverlayPage(
        urlKey: key,
        url: url,
        pageWidth: pageWidth,
        scrollHeight: scrollHeight,
        bubbles: [for (final bubble in bubbles) bubble.copyWith()],
        updatedAt: DateTime.now(),
      ),
    };
    await _persist();
  }

  Future<void> remove(String urlOrKey) async {
    final key = overlayUrlKey(urlOrKey);
    if (key.isEmpty || !pages.containsKey(key)) return;
    pages = {
      for (final entry in pages.entries)
        if (entry.key != key) entry.key: entry.value,
    };
    await _persist();
  }

  Future<void> replaceAll(Map<String, OverlayPage> next) async {
    pages = {
      for (final entry in next.entries)
        if (overlayUrlKey(entry.key).isNotEmpty)
          overlayUrlKey(entry.key): entry.value.copyWith(
            urlKey: overlayUrlKey(entry.key),
          ),
    };
    await _persist();
  }

  Future<void> mergeIncoming(Map<String, OverlayPage> incoming) async {
    pages = mergeOverlayPages(pages, incoming);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(overlayStoreKey, encodeOverlayPagesJson(pages));
    notifyListeners();
  }
}
