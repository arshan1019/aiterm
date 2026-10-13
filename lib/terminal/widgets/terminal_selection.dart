import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../../app/theme.dart';
import '../link_detector.dart';

/// Selection behaviour for the terminal, built on xterm's selection:
///
/// * Tapping a URL selects all of it, across wrapped rows, and offers
///   Open / Copy. A long-press or double-tap that lands inside a URL is
///   widened to the whole URL, so there are no handles to drag.
/// * Any other selection gets Copy / Paste; a long-press on empty space
///   offers Paste.
///
/// The toolbar is the platform's own text-selection toolbar, shown once the
/// finger lifts and hidden while touching, so it never covers a drag.
class TerminalSelection extends StatefulWidget {
  final Terminal terminal;
  final TerminalController controller;
  final GlobalKey<TerminalViewState> viewKey;
  final ValueChanged<String> onPaste;
  final ValueChanged<String> onOpenUrl;

  /// False while the terminal is in a background tab or another screen.
  final bool visible;
  final Widget child;

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

  @override
  State<TerminalSelection> createState() => _TerminalSelectionState();
}

class _TerminalSelectionState extends State<TerminalSelection> {
  final _menu = OverlayPortalController();
  Link? _link;
  Offset? _pasteAt; // global position of a long-press on empty space

  bool _touching = false;
  Offset _downAt = Offset.zero;
  Duration _downStamp = Duration.zero;
  bool _moved = false;
  bool _adjusting = false;
  int _shown = 0; // restarts the fade-in each time the toolbar appears

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

  /// A tap at [global]: if it's on a URL, select the whole URL.
  ///
  /// Taps are detected here rather than through TerminalView.onTapUp, which
  /// xterm 4.0.0 never calls.
  void _tapAt(Offset global) {
    final render = widget.viewKey.currentState?.renderTerminal;
    if (!mounted || render == null || !render.attached) return;
    final cell = render.getCellOffset(render.globalToLocal(global));
    final link = linkAt(_rows, CellPos(cell.x, cell.y));
    if (link == null) return;
    HapticFeedback.selectionClick();
    _select(link);
    _show();
  }

  void _select(Link link) {
    final buffer = widget.terminal.buffer;
    _link = link;
    _adjusting = true;
    widget.controller.setSelection(
      buffer.createAnchor(link.begin.x, link.begin.y),
      buffer.createAnchor(link.end.x, link.end.y),
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
    if (!_touching) _show();
  }

  void _onOutput() {
    // Output can scroll the selection; keep the toolbar attached to it.
    if (_menu.isShowing && mounted) setState(() {});
  }

  void _show() {
    if (!mounted) return;
    if (!_menu.isShowing) _shown++;
    setState(() {});
    _menu.show();
  }

  void _hide() {
    if (_menu.isShowing) _menu.hide();
  }

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
    final held = e.timeStamp - _downStamp;
    if (!_moved && held < kLongPressTimeout) {
      // After this event finishes dispatching: xterm handles the same tap
      // (clearing any old selection) before we select the URL.
      final at = e.position;
      Future.microtask(() => _tapAt(at));
      return;
    }
    if (widget.controller.selection != null) {
      _show();
    } else if (!_moved) {
      HapticFeedback.selectionClick();
      _pasteAt = e.position;
      _show();
    }
  }

  void _clear() {
    _pasteAt = null;
    _link = null;
    _hide();
    widget.controller.clearSelection();
  }

  void _copy() {
    final sel = widget.controller.selection;
    final text = _link?.url ??
        (sel == null
            ? ''
            : widget.terminal.buffer
                .getText(sel)
                .split('\n')
                .map((l) => l.trimRight())
                .join('\n'));
    if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    _clear();
  }

  Future<void> _paste() async {
    _clear();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) widget.onPaste(text);
  }

  void _open() {
    final url = _link?.url;
    _clear();
    if (url != null) widget.onOpenUrl(url);
  }

  /// Global anchors above the selection's first row and below its last,
  /// kept inside the visible terminal.
  TextSelectionToolbarAnchors? _anchors() {
    if (_pasteAt case final p?) return TextSelectionToolbarAnchors(primaryAnchor: p);
    final render = widget.viewKey.currentState?.renderTerminal;
    final sel = widget.controller.selection?.normalized;
    if (render == null || sel == null || !render.attached) return null;
    final box = render.localToGlobal(Offset.zero) & render.size;
    final top = render.localToGlobal(render.getOffset(sel.begin));
    final bottom = render.localToGlobal(render.getOffset(sel.end)) + Offset(0, render.lineHeight);
    final x = sel.begin.y == sel.end.y ? (top.dx + bottom.dx) / 2 : box.center.dx;
    return TextSelectionToolbarAnchors(
      primaryAnchor: Offset(x, top.dy.clamp(box.top, box.bottom)),
      secondaryAnchor: Offset(x, bottom.dy.clamp(box.top, box.bottom)),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final anchors = _anchors();
    if (anchors == null) return const SizedBox.shrink();
    final hasSelection = widget.controller.selection != null && _pasteAt == null;
    final toolbar = AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: [
        if (_link != null) ContextMenuButtonItem(label: 'Open', onPressed: _open),
        if (hasSelection)
          ContextMenuButtonItem(
            label: _link != null ? 'Copy link' : null,
            type: ContextMenuButtonType.copy,
            onPressed: _copy,
          ),
        ContextMenuButtonItem(type: ContextMenuButtonType.paste, onPressed: _paste),
      ],
    );
    return TweenAnimationBuilder<double>(
      key: ValueKey(_shown),
      tween: Tween(begin: 0, end: 1),
      duration: Motion.quick,
      curve: Motion.enter,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: toolbar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _menu,
      overlayChildBuilder: _buildMenu,
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

class _BufferRows implements RowSource {
  final Buffer buffer;
  _BufferRows(this.buffer);

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
