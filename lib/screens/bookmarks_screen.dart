import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/overlay_page.dart';
import '../services/bookmark_store.dart';
import '../services/library_backup.dart';
import '../services/overlay_coords.dart';
import '../services/overlay_store.dart';
import '../theme.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({
    super.key,
    required this.store,
    required this.overlays,
  });

  final BookmarkStore store;
  final OverlayStore overlays;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  bool _busy = false;

  BookmarkStore get _store => widget.store;
  OverlayStore get _overlays => widget.overlays;
  late final Listenable _lists = Listenable.merge([_store, _overlays]);

  OverlayPage? _overlayForUrl(String url) => _overlays.getByUrl(url);

  Future<Bookmark?> _editDialog({Bookmark? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final url = TextEditingController(text: existing?.url ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null ? '新增書籤' : '編輯書籤'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '名稱',
                  hintText: '自訂名稱',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '網址',
                  hintText: 'https://',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
    final saved = result == true
        ? Bookmark(
            id: existing?.id ?? '',
            name: name.text.trim(),
            url: url.text.trim(),
          )
        : null;
    name.dispose();
    url.dispose();
    if (saved == null || saved.url.isEmpty) return null;
    return saved;
  }

  Future<void> _add() async {
    final bookmark = await _editDialog();
    if (bookmark == null) return;
    await _store.add(name: bookmark.name, url: bookmark.url);
  }

  Future<void> _edit(Bookmark bookmark) async {
    final next = await _editDialog(existing: bookmark);
    if (next == null) return;
    await _store.update(bookmark.copyWith(name: next.name, url: next.url));
  }

  Future<void> _deleteBookmark(Bookmark bookmark) async {
    final overlay = _overlayForUrl(bookmark.url);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除書籤'),
        content: Text(
          overlay == null
              ? '確定刪除「${bookmark.name}」？'
              : '確定刪除「${bookmark.name}」？本頁 overlay（${overlay.bubbles.length} 框）會保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok == true) await _store.remove(bookmark.id);
  }

  Future<void> _deleteOverlay(OverlayPage page) async {
    final title = overlayPageTitle(page);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除 overlay'),
        content: Text('確定刪除「$title」的 ${page.bubbles.length} 個文字框？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok == true) await _overlays.remove(page.urlKey);
  }

  Future<void> _bookmarkOverlay(OverlayPage page) async {
    final url = page.url.isNotEmpty ? page.url : page.urlKey;
    await _store.add(name: overlayPageTitle(page), url: url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入書籤')),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final json = encodeLibraryJson(
        bookmarks: _store.items,
        overlays: _overlays.pages,
      );
      final bytes = Uint8List.fromList(utf8.encode(json));
      final uri = await FilePicker.saveFile(
        dialogTitle: '匯出書籤與 overlay',
        fileName: 'browser-translator-library.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        mimeType: 'application/json',
        bytes: bytes,
      );
      if (!mounted) return;
      if (uri == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已匯出 ${_store.items.length} 筆書籤、${_overlays.pages.length} 頁 overlay',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯出失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '匯入書籤與 overlay JSON',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      final incoming = decodeLibraryJson(utf8.decode(bytes));
      if (!mounted) return;
      final mode = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('匯入資料'),
          content: Text(
            '找到 ${incoming.bookmarks.length} 筆書籤、'
            '${incoming.overlayCount} 頁 overlay（${incoming.bubbleCount} 框）。'
            '要合併到現有資料，還是取代全部？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text('取代'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'merge'),
              child: const Text('合併'),
            ),
          ],
        ),
      );
      if (mode == 'merge') {
        if (incoming.bookmarks.isNotEmpty) {
          await _store.mergeIncoming(incoming.bookmarks);
        }
        if (incoming.overlays.isNotEmpty) {
          await _overlays.mergeIncoming(incoming.overlays);
        }
      } else if (mode == 'replace') {
        await _store.replaceAll(incoming.bookmarks);
        await _overlays.replaceAll(incoming.overlays);
      } else {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mode == 'merge' ? '已合併書籤與 overlay' : '已取代書籤與 overlay')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯入失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<_LibraryRow> _rows() {
    final bookmarkKeys = <String>{
      for (final item in _store.items) overlayUrlKey(item.url),
    };
    final rows = <_LibraryRow>[
      for (final bookmark in _store.items)
        _LibraryRow.bookmark(
          bookmark,
          overlay: _overlayForUrl(bookmark.url),
        ),
    ];
    final leftover = _overlays.pages.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final page in leftover) {
      if (bookmarkKeys.contains(page.urlKey)) continue;
      rows.add(_LibraryRow.overlayOnly(page));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('書籤'),
        actions: [
          IconButton(
            tooltip: '匯入 JSON',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          ListenableBuilder(
            listenable: _lists,
            builder: (context, _) {
              final canExport =
                  _store.items.isNotEmpty || _overlays.pages.isNotEmpty;
              return IconButton(
                tooltip: '匯出書籤與 overlay',
                onPressed: _busy || !canExport ? null : _export,
                icon: const Icon(Icons.file_download_outlined),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.stamp,
        foregroundColor: AppColors.paper,
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: _lists,
        builder: (context, _) {
          final rows = _rows();
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '還沒有書籤或 overlay。\n可新增網址，翻譯後 overlay 也會出現在這裡，並可一起匯出匯入。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            itemCount: rows.length,
            separatorBuilder: (context, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final subtitle = StringBuffer(row.url);
              if (row.overlay != null) {
                subtitle.write('\n${row.overlay!.bubbles.length} 個文字框');
              }
              return Material(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(row.title),
                  subtitle: Text(
                    subtitle.toString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, height: 1.35),
                  ),
                  isThreeLine: row.overlay != null,
                  leading: Icon(
                    row.isOverlayOnly
                        ? Icons.translate
                        : row.overlay == null
                            ? Icons.bookmark_outline
                            : Icons.bookmark,
                    color: row.overlay == null
                        ? AppColors.muted
                        : AppColors.stamp,
                  ),
                  onTap: () => Navigator.pop(context, row.url),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _edit(row.bookmark!);
                        case 'delete':
                          _deleteBookmark(row.bookmark!);
                        case 'bookmark':
                          _bookmarkOverlay(row.overlay!);
                        case 'deleteOverlay':
                          _deleteOverlay(row.overlay!);
                      }
                    },
                    itemBuilder: (context) => [
                      if (row.bookmark != null)
                        const PopupMenuItem(value: 'edit', child: Text('編輯')),
                      if (row.isOverlayOnly)
                        const PopupMenuItem(
                          value: 'bookmark',
                          child: Text('加入書籤'),
                        ),
                      if (row.overlay != null)
                        const PopupMenuItem(
                          value: 'deleteOverlay',
                          child: Text('刪除 overlay'),
                        ),
                      if (row.bookmark != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('刪除書籤'),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LibraryRow {
  const _LibraryRow._({
    required this.title,
    required this.url,
    required this.bookmark,
    required this.overlay,
    required this.isOverlayOnly,
  });

  factory _LibraryRow.bookmark(Bookmark bookmark, {OverlayPage? overlay}) {
    return _LibraryRow._(
      title: bookmark.name,
      url: bookmark.url,
      bookmark: bookmark,
      overlay: overlay,
      isOverlayOnly: false,
    );
  }

  factory _LibraryRow.overlayOnly(OverlayPage page) {
    return _LibraryRow._(
      title: overlayPageTitle(page),
      url: page.url.isNotEmpty ? page.url : page.urlKey,
      bookmark: null,
      overlay: page,
      isOverlayOnly: true,
    );
  }

  final String title;
  final String url;
  final Bookmark? bookmark;
  final OverlayPage? overlay;
  final bool isOverlayOnly;
}
