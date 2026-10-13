import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
// ignore: implementation_imports
import 'package:xterm/src/ui/render.dart' show RenderTerminal;
import '../../app/theme.dart';
import '../link_detector.dart';

/// Selection for the terminal, built on xterm's selection:
///
/// * Tapping a URL selects all of it, across wrapped rows, and offers
///   Open / Copy. A long-press or double-tap inside a URL widens to the
///   whole URL.
/// * Long-press selects a word; drag the handles to adjust, with a
///   magnifier under the finger. Long-press on empty space offers Paste.
///
/// Handles and the toolbar live in the app overlay. The toolbar shows once
/// the finger lifts and hides while touching or dragging, so it never
/// covers what the user is doing.
class TerminalSelection extends StatefulWidget {
  const TerminalSelection({
    super.key,
    required this.terminal,
    required this.controller,
    required this.viewKey,
    required this.onPaste,
    required this.onOpenUrl,
    required this.visible,
    required this.child,
  });

  final Terminal terminal;
  final TerminalController controller;
  final GlobalKey<TerminalViewState> viewKey;
  final ValueChanged<String> onPaste;
  final ValueChanged<String> onOpenUrl;

  /// False while the terminal is in a background tab or another screen.
  final bool visible;
  final Widget child;

  @override
  State<TerminalSelection> createState() => _TerminalSelectionState();
}

enum _End { start, end }

class _TerminalSelectionState extends State<TerminalSelection> {
  final _overlay = OverlayPortalController();
  Link? _link;
  Offset? _pasteAt; // global position of a long-press on empty space

  // Touches on the terminal itself (handles are separate, in the overlay).
  bool _touching = false;
  Offset _downAt = Offset.zero;
  Duration _downStamp = Duration.zero;
  bool _moved = false;

  // Handle drag in progress.
  _End? _dragging;
  Offset _grab = Offset.zero; // finger → handle tip
  Offset _finger = Offset.zero;

  bool _adjusting = false;
  int _shown = 0; // restarts the toolbar fade-in each time it appears

  RenderTerminal? get _render {
    final r = widget.viewKey.currentState?.renderTerminal;
    return r != null && r.attached ? r : null;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSelection);
    widget.terminal.addListener(_onOutput);
  }

  @override
  void didUpdateWidget(TerminalSelection old) {
    super.didUpdateWidget(old);
    if (!widget.visible && old.visible) {
      // Can't change the selection mid-build; it notifies listeners.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clear();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSelection);
    widget.terminal.removeListener(_onOutput);
    super.dispose();
  }

  _BufferRows get _rows => _BufferRows(widget.terminal.buffer);

  // ── Selecting ──────────────────────────────────────────────────────────

  /// A tap at [global]: on a URL, select the whole URL. Taps are detected
  /// here rather than via TerminalView.onTapUp, which xterm 4.0.0 never calls.
  void _tapAt(Offset global) {
    final render = _render;
    if (!mounted || render == null) return;
    final cell = render.getCellOffset(render.globalToLocal(global));
    final link = linkAt(_rows, CellPos(cell.x, cell.y));
    if (link == null) {
      // A plain tap clears the selection (xterm); one still here came from
      // a long-press or double-tap, so show its handles and toolbar.
      if (widget.controller.selection != null) {
        _shown++;
        _refresh();
      }
      return;
    }
    HapticFeedback.selectionClick();
    _select(link);
    _refresh();
  }

  void _select(Link link) {
    _link = link;
    _setRange(CellOffset(link.begin.x, link.begin.y), CellOffset(link.end.x, link.end.y));
  }

  void _setRange(CellOffset begin, CellOffset end) {
    final buffer = widget.terminal.buffer;
    _adjusting = true;
    widget.controller.setSelection(
      buffer.createAnchorFromOffset(begin),
      buffer.createAnchorFromOffset(end),
      mode: SelectionMode.line,
    );
    _adjusting = false;
  }

  void _onSelection() {
    if (_adjusting) return;
    final sel = widget.controller.selection?.normalized;
    if (sel == null) {
      _link = null;
      if (_pasteAt == null) _hide();
      return;
    }
    _pasteAt = null;
    if (_dragging == null) {
      // A word selected inside a URL grows to the whole URL.
      final begin = CellPos(sel.begin.x, sel.begin.y);
      final last = CellPos(sel.end.x - 1, sel.end.y);
      final link = linkAt(_rows, begin);
      if (link != null && link.covers(begin, last)) {
        if (link.begin != begin || link.end != CellPos(sel.end.x, sel.end.y)) _select(link);
        _link = link;
      } else {
        _link = null;
      }
    }
    if (!_touching) _refresh();
  }

  void _onOutput() {
    // Output can scroll the selection; keep handles and toolbar on it.
    if (_overlay.isShowing && mounted) setState(() {});
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    if (!_overlay.isShowing) {
      _shown++;
      _overlay.show();
    }
  }

  void _hide() {
    if (_overlay.isShowing) _overlay.hide();
  }

  void _clear() {
    _pasteAt = null;
    _link = null;
    _dragging = null;
    _hide();
    widget.controller.clearSelection();
  }

  // ── Touches on the terminal ────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _touching = true;
    _moved = false;
    _downAt = e.position;
    _downStamp = e.timeStamp;
    _pasteAt = null;
    _hide();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if ((e.position - _downAt).distance > kTouchSlop) _moved = true;
  }

  void _onPointerUp(PointerUpEvent e) {
    _touching = false;
    if (!_moved && e.timeStamp - _downStamp < kLongPressTimeout) {
      // After this event finishes dispatching: xterm handles the same tap
      // (clearing any old selection) before we look for a URL.
      final at = e.position;
      Future.microtask(() => _tapAt(at));
      return;
    }
    if (widget.controller.selection != null) {
      _shown++;
      _refresh();
    } else if (!_moved) {
      HapticFeedback.selectionClick();
      _pasteAt = e.position;
      _refresh();
    }
  }

  // ── Handles ────────────────────────────────────────────────────────────

  /// Global position of the boundary before cell [c] at the bottom of its row.
  Offset _tip(RenderTerminal r, CellOffset c) => r.localToGlobal(r.getOffset(c) + Offset(0, r.lineHeight));

  void _dragStart(_End end, DragStartDetails d) {
    final render = _render;
    final sel = widget.controller.selection?.normalized;
    if (render == null || sel == null) return;
    final tip = _tip(render, end == _End.start ? sel.begin : sel.end);
    setState(() {
      _dragging = end;
      _grab = tip - d.globalPosition;
      _finger = d.globalPosition;
      _link = null; // a hand-adjusted range copies as text, not as a link
    });
    HapticFeedback.selectionClick();
  }

  void _dragUpdate(DragUpdateDetails d) {
    final render = _render;
    final sel = widget.controller.selection?.normalized;
    final end = _dragging;
    if (render == null || sel == null || end == null) return;
    _finger = d.globalPosition;
    // The tip sits on the bottom edge of its row; aim at the row's middle,
    // and round to the nearest character boundary.
    final aim = render.globalToLocal(d.globalPosition + _grab - Offset(0, render.lineHeight / 2));
    final cellWidth = render.cellSize.width;
    final cell = render.getCellOffset(aim);
    final width = widget.terminal.viewWidth;
    final col = ((aim.dx - render.getOffset(CellOffset(0, cell.y)).dx) / cellWidth).round().clamp(0, width);
    final boundary = CellOffset(col, cell.y);

    int index(CellOffset c) => c.y * (width + 1) + c.x;
    var begin = sel.begin, finish = sel.end;
    if (end == _End.start) {
      if (index(boundary) >= index(finish)) return; // keep at least one cell
      begin = boundary;
    } else {
      if (index(boundary) <= index(begin)) return;
      finish = boundary;
    }
    if (begin != sel.begin || finish != sel.end) {
      HapticFeedback.selectionClick();
      _setRange(begin, finish);
    }
    setState(() {});
  }

  void _dragEnd() {
    setState(() => _dragging = null);
    _shown++;
    _refresh();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  void _copy() {
    final sel = widget.controller.selection;
    final text = _link?.url ??
        (sel == null
            ? ''
            : widget.terminal.buffer.getText(sel).split('\n').map((l) => l.trimRight()).join('\n'));
    if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    _clear();
  }

  Future<void> _paste() async {
    _clear();
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null && text.isNotEmpty) widget.onPaste(text);
  }

  void _selectAll() {
    final buffer = widget.terminal.buffer;
    _link = null;
    _setRange(CellOffset(0, 0), CellOffset(widget.terminal.viewWidth, buffer.lines.length - 1));
    _shown++;
    _refresh();
  }

  void _open() {
    final url = _link?.url;
    _clear();
    if (url != null) widget.onOpenUrl(url);
  }

  // ── Overlay: handles, magnifier, toolbar ───────────────────────────────

  Widget _buildOverlay(BuildContext context) {
    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;
    Offset local(Offset global) => overlayBox?.globalToLocal(global) ?? global;
    final render = _render;
    final sel = widget.controller.selection?.normalized;
    final c = context.colors;
    final children = <Widget>[];

    if (render != null && sel != null && _pasteAt == null) {
      final view = render.localToGlobal(Offset.zero) & render.size;
      final start = _tip(render, sel.begin), end = _tip(render, sel.end);
      for (final (which, tip) in [(_End.start, start), (_End.end, end)]) {
        // Only while the boundary is on screen.
        if (tip.dy < view.top + render.lineHeight / 2 || tip.dy > view.bottom + 1) continue;
        children.add(_Handle(
          key: ValueKey(which),
          tip: local(tip),
          left: which == _End.start,
          color: c.accent,
          onStart: (d) => _dragStart(which, d),
          onUpdate: _dragUpdate,
          onEnd: _dragEnd,
        ));
      }
      if (_dragging case final which?) {
        final tip = which == _End.start ? start : end;
        final rowCenter = tip - Offset(0, render.lineHeight / 2);
        children.add(_Magnifier(
          center: local(Offset(_finger.dx, rowCenter.dy - render.lineHeight - 36)),
          focus: Offset(0, render.lineHeight + 36),
          border: c.border,
        ));
      }
    }

    if (_dragging == null && !_touching) {
      if (_anchors(render, sel) case final anchors?) {
        final hasSelection = sel != null && _pasteAt == null;
        children.add(Positioned.fill(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_shown),
            tween: Tween(begin: 0, end: 1),
            duration: Motion.quick,
            curve: Motion.enter,
            builder: (context, t, child) => Opacity(opacity: t, child: child),
            child: AdaptiveTextSelectionToolbar.buttonItems(
              anchors: TextSelectionToolbarAnchors(
                primaryAnchor: local(anchors.primaryAnchor),
                secondaryAnchor: anchors.secondaryAnchor == null ? null : local(anchors.secondaryAnchor!),
              ),
              buttonItems: [
                if (_link != null) ContextMenuButtonItem(label: 'Open', onPressed: _open),
                if (hasSelection)
                  ContextMenuButtonItem(
                    label: _link != null ? 'Copy link' : null,
                    type: ContextMenuButtonType.copy,
                    onPressed: _copy,
                  ),
                ContextMenuButtonItem(type: ContextMenuButtonType.paste, onPressed: _paste),
                if (_link == null) ContextMenuButtonItem(type: ContextMenuButtonType.selectAll, onPressed: _selectAll),
              ],
            ),
          ),
        ));
      }
    }
    return Stack(children: children);
  }

  /// Global anchors above the selection's first row and below its last
  /// (clear of the handles), kept inside the visible terminal.
  TextSelectionToolbarAnchors? _anchors(RenderTerminal? render, BufferRange? sel) {
    if (_pasteAt case final p?) return TextSelectionToolbarAnchors(primaryAnchor: p);
    if (render == null || sel == null) return null;
    final box = render.localToGlobal(Offset.zero) & render.size;
    final top = render.localToGlobal(render.getOffset(sel.begin));
    final bottom = _tip(render, sel.end) + const Offset(0, _Handle.size);
    final x = sel.begin.y == sel.end.y ? (top.dx + bottom.dx) / 2 : box.center.dx;
    return TextSelectionToolbarAnchors(
      primaryAnchor: Offset(x, top.dy.clamp(box.top, box.bottom)),
      secondaryAnchor: Offset(x, bottom.dy.clamp(box.top, box.bottom)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: _buildOverlay,
      // A raw Listener sees every touch without joining the gesture arena,
      // so xterm's own tap, drag and scroll handling is untouched.
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: (_) => _touching = false,
        child: widget.child,
      ),
    );
  }
}

/// A teardrop selection handle whose point sits on the selection boundary,
/// with a touch target much larger than what's drawn.
class _Handle extends StatelessWidget {
  const _Handle({
    super.key,
    required this.tip,
    required this.left,
    required this.color,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  static const size = 22.0;
  static const _touch = 48.0;

  final Offset tip;
  final bool left;
  final Color color;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    // The drawn drop: its pointed corner touches the tip (top-right for the
    // start handle, top-left for the end handle).
    final dropLeft = left ? tip.dx - size : tip.dx;
    return Positioned(
      left: dropLeft + size / 2 - _touch / 2,
      top: tip.dy - 6,
      width: _touch,
      height: _touch,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: onStart,
        onPanUpdate: onUpdate,
        onPanEnd: (_) => onEnd(),
        onPanCancel: onEnd,
        child: Align(
          alignment: const Alignment(0, -0.62),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(left ? size : 0),
                topRight: Radius.circular(left ? 0 : size),
                bottomLeft: const Radius.circular(size),
                bottomRight: const Radius.circular(size),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlarged view of the text under the finger while dragging a handle.
class _Magnifier extends StatelessWidget {
  const _Magnifier({required this.center, required this.focus, required this.border});

  static const _size = Size(112, 44);

  /// Where the magnifier sits (overlay coordinates).
  final Offset center;

  /// From the magnifier's center to the point it magnifies.
  final Offset focus;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - _size.width / 2,
      top: center.dy - _size.height / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: _size,
          magnificationScale: 1.35,
          focalPointOffset: focus,
          decoration: MagnifierDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_size.height / 2),
              side: BorderSide(color: border),
            ),
            shadows: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3))],
          ),
        ),
      ),
    );
  }
}

class _BufferRows implements RowSource {
  _BufferRows(this.buffer);

  final Buffer buffer;

  @override
  int get rowCount => buffer.lines.length;

  @override
  int get width => buffer.viewWidth;

  @override
  bool isWrapped(int y) => y > 0 && y < buffer.lines.length && buffer.lines[y].isWrapped;

  @override
  String row(int y) {
    final line = buffer.lines[y];
    final out = StringBuffer();
    for (var x = 0; x < width; x++) {
      final cp = x < line.length ? line.getCodePoint(x) : 0;
      // One character per cell: blanks and wide-glyph tails become spaces.
      out.writeCharCode(cp == 0 || cp > 0xFFFF ? 0x20 : cp);
    }
    return out.toString();
  }
}
