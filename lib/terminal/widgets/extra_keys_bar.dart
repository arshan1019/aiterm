import 'dart:async';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../../app/theme.dart';
import '../terminal_session.dart';

/// Keys a phone keyboard lacks: two rows of equal-width keys, so the bar
/// lines up on every screen width. Keys act on touch-down like a real
/// keyboard; arrows repeat while held.
class ExtraKeysBar extends StatelessWidget {
  const ExtraKeysBar({super.key, required this.session, required this.onAsk});

  final TerminalSession session;
  final VoidCallback onAsk;

  static const rowHeight = 38.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = session.modifiers;
    Widget text(String label, VoidCallback onPress) => _Key(label: label, onPress: onPress);
    Widget key(String label, TerminalKey k) => _Key(label: label, onPress: () => session.sendKey(k));
    Widget arrow(IconData icon, TerminalKey k) =>
        _Key(icon: icon, repeat: true, onPress: () => session.sendKey(k));

    return ColoredBox(
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: ListenableBuilder(
          listenable: m,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row([
                ValueListenableBuilder(
                  valueListenable: session.state,
                  builder: (context, state, _) => _Key(
                    icon: Icons.auto_awesome_rounded,
                    accent: true,
                    onPress: state == SessionState.running ? onAsk : null,
                  ),
                ),
                key('ESC', TerminalKey.escape),
                text('/', () => session.sendText('/')),
                text('-', () => session.sendText('-')),
                text('|', () => session.sendText('|')),
                arrow(Icons.keyboard_arrow_up_rounded, TerminalKey.arrowUp),
              ]),
              _row([
                key('TAB', TerminalKey.tab),
                _Key(label: 'CTRL', active: m.ctrl || m.volumeCtrl, onPress: m.toggleCtrl),
                _Key(label: 'ALT', active: m.alt, onPress: m.toggleAlt),
                arrow(Icons.keyboard_arrow_left_rounded, TerminalKey.arrowLeft),
                arrow(Icons.keyboard_arrow_down_rounded, TerminalKey.arrowDown),
                arrow(Icons.keyboard_arrow_right_rounded, TerminalKey.arrowRight),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> keys) => SizedBox(
        height: rowHeight,
        child: Row(children: [for (final k in keys) Expanded(child: k)]),
      );
}

class _Key extends StatefulWidget {
  const _Key({this.label, this.icon, required this.onPress, this.active = false, this.accent = false, this.repeat = false});

  final String? label;
  final IconData? icon;
  final VoidCallback? onPress;
  final bool active;
  final bool accent;
  final bool repeat;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;
  Timer? _repeat;

  void _press() {
    final onPress = widget.onPress;
    if (onPress == null) return;
    setState(() => _down = true);
    onPress();
    if (widget.repeat) {
      _repeat = Timer(const Duration(milliseconds: 380), () {
        _repeat = Timer.periodic(const Duration(milliseconds: 55), (_) => widget.onPress?.call());
      });
    }
  }

  void _release() {
    _repeat?.cancel();
    if (_down) setState(() => _down = false);
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPress != null;
    final fg = !enabled
        ? c.border
        : widget.active
            ? c.bg
            : widget.accent
                ? c.accent
                : c.text;
    final bg = widget.active
        ? c.accent
        : _down
            ? c.surfaceAlt
            : c.surface;
    return Listener(
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.enter,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
          alignment: Alignment.center,
          child: widget.icon != null
              ? Icon(widget.icon, size: 22, color: fg)
              : Text(
                  widget.label!,
                  style: TextStyle(
                    color: fg,
                    fontSize: widget.accent ? 16 : 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}
