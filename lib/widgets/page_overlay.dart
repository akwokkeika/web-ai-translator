import 'package:flutter/material.dart';

import '../models/overlay_page.dart';
import '../theme.dart';
import '../services/overlay_coords.dart';
import '../services/page_metrics.dart';
import 'bubble_text.dart';

class PageOverlayLayer extends StatefulWidget {
  const PageOverlayLayer({
    super.key,
    required this.bubbles,
    required this.metrics,
    required this.editing,
    required this.minFontPx,
    required this.showOriginal,
    required this.onChanged,
  });

  final List<OverlayBubble> bubbles;
  final WebScrollMetrics metrics;
  final bool editing;
  final double minFontPx;
  final bool showOriginal;
  final ValueChanged<List<OverlayBubble>> onChanged;

  @override
  State<PageOverlayLayer> createState() => _PageOverlayLayerState();
}

class _PageOverlayLayerState extends State<PageOverlayLayer> {
  static const _minLocal = 36.0;

  List<OverlayBubble> _working = [];
  String? _selectedId;
  _DragSession? _drag;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _working = widget.bubbles;
  }

  @override
  void didUpdateWidget(PageOverlayLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && !identical(widget.bubbles, oldWidget.bubbles)) {
      _working = widget.bubbles;
      if (_selectedId != null &&
          _working.every((item) => item.id != _selectedId)) {
        _selectedId = null;
      }
    }
    if (!widget.editing) {
      _drag = null;
      _selectedId = null;
    }
  }

  OverlayBubble? _byId(String? id) {
    if (id == null) return null;
    for (final bubble in _working) {
      if (bubble.id == id) return bubble;
    }
    return null;
  }

  void _commit(List<OverlayBubble> next) {
    _working = next;
    widget.onChanged(next);
  }

  Future<void> _editText(OverlayBubble bubble) async {
    final result = await showOverlayTextDialog(
      context: context,
      bubble: bubble,
    );
    if (!mounted || result == null) return;
    if (result.delete || result.text.trim().isEmpty) {
      _commit([
        for (final item in _working)
          if (item.id != bubble.id) item,
      ]);
      setState(() => _selectedId = null);
      return;
    }
    _commit([
      for (final item in _working)
        if (item.id == bubble.id)
          item.copyWith(translated: result.text.trim())
        else
          item,
    ]);
  }

  void _onPanStart(DragStartDetails details, Size size) {
    if (!widget.editing) return;
    _working = [for (final item in widget.bubbles) item.copyWith()];
    _dragging = true;
    final local = details.localPosition;
    final space = _OverlaySpace(size, widget.metrics);

    if (_selectedId != null) {
      final selected = _byId(_selectedId);
      if (selected != null) {
        final kind = space.hitHandle(selected, local);
        if (kind != null) {
          setState(() {
            _drag = _DragSession(
              kind: kind,
              bubbleId: selected.id,
              start: local,
              origin: selected.copyWith(),
            );
          });
          return;
        }
        if (space.bubbleRect(selected).inflate(6).contains(local)) {
          setState(() {
            _drag = _DragSession(
              kind: _DragKind.move,
              bubbleId: selected.id,
              start: local,
              origin: selected.copyWith(),
            );
          });
          return;
        }
      }
    }

    for (final bubble in _working.reversed) {
      if (space.bubbleRect(bubble).inflate(4).contains(local)) {
        setState(() {
          _selectedId = bubble.id;
          _drag = _DragSession(
            kind: _DragKind.move,
            bubbleId: bubble.id,
            start: local,
            origin: bubble.copyWith(),
          );
        });
        return;
      }
    }

    setState(() {
      _selectedId = null;
      _drag = _DragSession(
        kind: _DragKind.create,
        bubbleId: null,
        start: local,
        origin: null,
        current: local,
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final drag = _drag;
    if (drag == null) return;
    final local = details.localPosition;
    final space = _OverlaySpace(size, widget.metrics);

    if (drag.kind == _DragKind.create) {
      setState(() => _drag = drag.copyWith(current: local));
      return;
    }

    final origin = drag.origin;
    if (origin == null) return;
    final delta = local - drag.start;
    final next = space.applyDrag(origin, drag.kind, delta);
    setState(() {
      _working = [
        for (final item in _working)
          if (item.id == origin.id) next else item,
      ];
    });
  }

  Future<void> _onPanEnd(Size size) async {
    final drag = _drag;
    _dragging = false;
    if (drag == null) {
      setState(() {});
      return;
    }

    if (drag.kind == _DragKind.create && drag.current != null) {
      final rect = Rect.fromPoints(drag.start, drag.current!);
      _drag = null;
      if (rect.width < _minLocal || rect.height < _minLocal) {
        setState(() {});
        return;
      }
      final cssRect = _OverlaySpace(size, widget.metrics).toCssRect(rect);
      final created = overlayBubbleFromRect(
        left: cssRect.left,
        top: cssRect.top,
        width: cssRect.width,
        height: cssRect.height,
        metrics: widget.metrics,
      );
      final result = await showOverlayTextDialog(
        context: context,
        bubble: created,
        title: '新增對話框',
      );
      if (!mounted) return;
      if (result == null || result.delete || result.text.trim().isEmpty) {
        setState(() {});
        return;
      }
      final saved = created.copyWith(translated: result.text.trim());
      _commit([..._working, saved]);
      setState(() => _selectedId = saved.id);
      return;
    }

    _drag = null;
    _commit(_working);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.width <= 0 || size.height <= 0) {
          return const SizedBox.expand();
        }
        final space = _OverlaySpace(size, widget.metrics);
        final createRect = _drag?.kind == _DragKind.create && _drag?.current != null
            ? Rect.fromPoints(_drag!.start, _drag!.current!)
            : null;

        final stack = Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final bubble in _working)
              if (space.isVisible(bubble))
                _BubbleChrome(
                  bubble: bubble,
                  rect: space.bubbleRect(bubble),
                  minFontPx: widget.minFontPx,
                  showOriginal: widget.showOriginal,
                  editing: widget.editing,
                  selected: widget.editing && bubble.id == _selectedId,
                  onTap: () {
                    if (widget.editing) {
                      setState(() => _selectedId = bubble.id);
                    } else {
                      _editText(bubble);
                    }
                  },
                  onDelete: widget.editing
                      ? () {
                          _commit([
                            for (final item in _working)
                              if (item.id != bubble.id) item,
                          ]);
                          setState(() => _selectedId = null);
                        }
                      : null,
                  onEdit: widget.editing ? () => _editText(bubble) : null,
                ),
            if (createRect != null)
              Positioned.fromRect(
                rect: createRect,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.stamp.withValues(alpha: 0.18),
                      border: Border.all(color: AppColors.stamp, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
          ],
        );

        if (!widget.editing) return stack;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _onPanStart(details, size),
          onPanUpdate: (details) => _onPanUpdate(details, size),
          onPanEnd: (_) => _onPanEnd(size),
          onPanCancel: () {
            _dragging = false;
            _drag = null;
            _working = widget.bubbles;
            setState(() {});
          },
          child: stack,
        );
      },
    );
  }
}

class OverlayToolbar extends StatelessWidget {
  const OverlayToolbar({
    super.key,
    required this.enabled,
    required this.editing,
    required this.busy,
    required this.count,
    required this.showOriginal,
    required this.onToggleEnabled,
    required this.onToggleEditing,
    required this.onToggleOriginal,
    required this.onNudge,
    required this.onClear,
  });

  final bool enabled;
  final bool editing;
  final bool busy;
  final int count;
  final bool showOriginal;
  final VoidCallback onToggleEnabled;
  final VoidCallback onToggleEditing;
  final VoidCallback onToggleOriginal;
  final ValueChanged<double> onNudge;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          children: [
            FilterChip(
              selected: enabled,
              onSelected: busy ? null : (_) => onToggleEnabled(),
              label: Text(enabled ? 'Overlay 開' : 'Overlay'),
              visualDensity: VisualDensity.compact,
            ),
            if (enabled) ...[
              const SizedBox(width: 6),
              FilterChip(
                selected: editing,
                onSelected: busy ? null : (_) => onToggleEditing(),
                label: Text(editing ? '編輯中' : '閱讀'),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Text(
                '$count 框',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              IconButton(
                tooltip: showOriginal ? '顯示譯文' : '顯示原文',
                onPressed: onToggleOriginal,
                icon: Icon(
                  showOriginal ? Icons.translate : Icons.notes,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: '整頁上移',
                onPressed: count == 0 ? null : () => onNudge(-24),
                icon: const Icon(Icons.keyboard_arrow_up, size: 22),
              ),
              IconButton(
                tooltip: '整頁下移',
                onPressed: count == 0 ? null : () => onNudge(24),
                icon: const Icon(Icons.keyboard_arrow_down, size: 22),
              ),
              IconButton(
                tooltip: '清除本頁 overlay',
                onPressed: count == 0 ? null : onClear,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OverlayTextResult {
  const OverlayTextResult({required this.text, this.delete = false});
  final String text;
  final bool delete;
}

Future<OverlayTextResult?> showOverlayTextDialog({
  required BuildContext context,
  required OverlayBubble bubble,
  String title = '編輯譯文',
}) async {
  final controller = TextEditingController(text: bubble.translated);
  final result = await showDialog<OverlayTextResult>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bubble.original.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  bubble.original,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(hintText: '譯文'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const OverlayTextResult(text: '', delete: true),
            ),
            child: const Text('刪除'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              OverlayTextResult(text: controller.text),
            ),
            child: const Text('儲存'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

enum _DragKind { create, move, nw, ne, sw, se }

class _DragSession {
  const _DragSession({
    required this.kind,
    required this.bubbleId,
    required this.start,
    required this.origin,
    this.current,
  });

  final _DragKind kind;
  final String? bubbleId;
  final Offset start;
  final OverlayBubble? origin;
  final Offset? current;

  _DragSession copyWith({Offset? current}) {
    return _DragSession(
      kind: kind,
      bubbleId: bubbleId,
      start: start,
      origin: origin,
      current: current ?? this.current,
    );
  }
}

class _OverlaySpace {
  _OverlaySpace(this.size, this.metrics);

  final Size size;
  final WebScrollMetrics metrics;

  double get _sy => size.height / metrics.innerHeight;
  double get _sx => size.width / metrics.innerWidth;

  Rect bubbleRect(OverlayBubble bubble) {
    return Rect.fromLTWH(
      bubble.x * size.width,
      (bubble.yPx - metrics.scrollY) * _sy,
      bubble.w * size.width,
      bubble.hPx * _sy,
    );
  }

  bool isVisible(OverlayBubble bubble) {
    final rect = bubbleRect(bubble);
    return rect.bottom >= -8 && rect.top <= size.height + 8;
  }

  Rect toCssRect(Rect local) {
    return Rect.fromLTWH(
      local.left / _sx,
      local.top / _sy,
      local.width / _sx,
      local.height / _sy,
    );
  }

  _DragKind? hitHandle(OverlayBubble bubble, Offset local) {
    final rect = bubbleRect(bubble);
    bool near(Offset point) => (local - point).distance <= 22;
    if (near(rect.topLeft)) return _DragKind.nw;
    if (near(rect.topRight)) return _DragKind.ne;
    if (near(rect.bottomLeft)) return _DragKind.sw;
    if (near(rect.bottomRight)) return _DragKind.se;
    return null;
  }

  OverlayBubble applyDrag(
    OverlayBubble origin,
    _DragKind kind,
    Offset localDelta,
  ) {
    var left = origin.x * metrics.innerWidth;
    var top = origin.yPx;
    var width = origin.w * metrics.innerWidth;
    var height = origin.hPx;
    final dx = localDelta.dx / _sx;
    final dy = localDelta.dy / _sy;

    switch (kind) {
      case _DragKind.move:
        left += dx;
        top += dy;
      case _DragKind.nw:
        left += dx;
        top += dy;
        width -= dx;
        height -= dy;
      case _DragKind.ne:
        top += dy;
        width += dx;
        height -= dy;
      case _DragKind.sw:
        left += dx;
        width -= dx;
        height += dy;
      case _DragKind.se:
        width += dx;
        height += dy;
      case _DragKind.create:
        break;
    }

    if (width < 28) width = 28;
    if (height < 22) height = 22;
    if (left < 0) left = 0;
    if (left + width > metrics.innerWidth) {
      left = (metrics.innerWidth - width).clamp(0, metrics.innerWidth);
    }
    final x = (left / metrics.innerWidth).clamp(0.0, 1.0);
    final w = (width / metrics.innerWidth).clamp(0.02, 1.0 - x);
    return origin.copyWith(x: x, yPx: top, w: w, hPx: height);
  }
}

class _BubbleChrome extends StatelessWidget {
  const _BubbleChrome({
    required this.bubble,
    required this.rect,
    required this.minFontPx,
    required this.showOriginal,
    required this.editing,
    required this.selected,
    required this.onTap,
    this.onDelete,
    this.onEdit,
  });

  final OverlayBubble bubble;
  final Rect rect;
  final double minFontPx;
  final bool showOriginal;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final text = showOriginal && bubble.original.isNotEmpty
        ? bubble.original
        : bubble.translated;
    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: AppColors.paper.withValues(alpha: selected ? 0.98 : 0.94),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: selected
                  ? const BorderSide(color: AppColors.stamp, width: 2)
                  : editing
                      ? BorderSide(
                          color: AppColors.stamp.withValues(alpha: 0.55),
                        )
                      : BorderSide.none,
            ),
            child: InkWell(
              onTap: onTap,
              onLongPress: onEdit,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: BubbleText(text: text, minFontSize: minFontPx),
              ),
            ),
          ),
          if (selected) ...[
            for (final alignment in const [
              Alignment.topLeft,
              Alignment.topRight,
              Alignment.bottomLeft,
              Alignment.bottomRight,
            ])
              Align(
                alignment: alignment,
                child: IgnorePointer(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.stamp,
                      border: Border.all(color: AppColors.paper, width: 1.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -8,
              top: -8,
              child: Material(
                color: AppColors.stamp,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: AppColors.paper),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
