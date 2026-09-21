import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';

String normalizeBookmarkUrl(String raw) {
  var url = raw.trim();
  if (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

String encodeBookmarksJson(List<Bookmark> items) {
  return const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'bookmarks': [for (final item in items) item.toJson()],
  });
}

List<Bookmark> decodeBookmarksJson(String raw) {
  final decoded = jsonDecode(raw);
  final List<dynamic> list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map && decoded['bookmarks'] is List) {
    list = decoded['bookmarks'] as List;
  } else {
    throw const FormatException('書籤 JSON 格式不正確，需要 bookmarks 陣列');
  }

  final items = <Bookmark>[];
  for (final entry in list) {
    if (entry is! Map) continue;
    final bookmark = Bookmark.fromJson(Map<String, dynamic>.from(entry));
    if (bookmark.url.isEmpty) continue;
    items.add(
      Bookmark(
        id: bookmark.id.isEmpty ? _newId() : bookmark.id,
        name: bookmark.name.isEmpty ? bookmark.url : bookmark.name,
        url: bookmark.url,
      ),
    );
  }
  return items;
}

List<Bookmark> mergeBookmarks(List<Bookmark> current, List<Bookmark> incoming) {
  final merged = [...current];
  final indexByUrl = <String, int>{
    for (var i = 0; i < merged.length; i++)
      normalizeBookmarkUrl(merged[i].url): i,
  };
  for (final item in incoming) {
    final key = normalizeBookmarkUrl(item.url);
    if (key.isEmpty) continue;
    final existing = indexByUrl[key];
    if (existing == null) {
      indexByUrl[key] = merged.length;
      merged.add(
        Bookmark(
          id: item.id.isEmpty ? _newId() : item.id,
          name: item.name,
          url: item.url,
        ),
      );
    } else if (item.name.isNotEmpty) {
      merged[existing] = merged[existing].copyWith(name: item.name);
    }
  }
  return merged;
}

String _newId() {
  final rand = Random();
  return '${DateTime.now().microsecondsSinceEpoch}-${rand.nextInt(1 << 32)}';
}

class BookmarkStore extends ChangeNotifier {
  List<Bookmark> items = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('bookmarks_json');
    if (raw == null || raw.trim().isEmpty) {
      items = [];
    } else {
      try {
        items = decodeBookmarksJson(raw);
      } on FormatException {
        items = [];
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bookmarks_json', encodeBookmarksJson(items));
    notifyListeners();
  }

  Future<void> add({required String name, required String url}) async {
    final trimmedUrl = url.trim();
    final trimmedName = name.trim().isEmpty ? trimmedUrl : name.trim();
    if (trimmedUrl.isEmpty) return;
    final key = normalizeBookmarkUrl(trimmedUrl);
    final index = items.indexWhere(
      (item) => normalizeBookmarkUrl(item.url) == key,
    );
    if (index >= 0) {
      items[index] = items[index].copyWith(name: trimmedName, url: trimmedUrl);
    } else {
      items = [
        ...items,
        Bookmark(id: _newId(), name: trimmedName, url: trimmedUrl),
      ];
    }
    await _persist();
  }

  Future<void> update(Bookmark bookmark) async {
    items = [
      for (final item in items)
        if (item.id == bookmark.id) bookmark else item,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    items = [for (final item in items) if (item.id != id) item];
    await _persist();
  }

  Future<void> replaceAll(List<Bookmark> next) async {
    items = next;
    await _persist();
  }

  Future<void> mergeIncoming(List<Bookmark> incoming) async {
    items = mergeBookmarks(items, incoming);
    await _persist();
  }
}
