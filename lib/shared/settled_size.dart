import 'dart:async';
import 'package:flutter/widgets.dart';

/// Lays [child] out at the last *settled* size.
///
/// While the available height keeps changing — the keyboard sliding in or
/// out resizes the body every frame — the child keeps its previous size,
/// pinned to the bottom edge and clipped, so its content rides along with
/// the keyboard. Once changes stop for [settle], the child takes the new
/// size in a single layout. For the terminal that means one reflow per
/// keyboard change instead of one per animation frame.
///
/// Width changes (rotation, split screen) apply immediately.
class SettledSize extends StatefulWidget {
  const SettledSize({super.key, required this.child, this.settle = const Duration(milliseconds: 90)});

  final Widget child;
  final Duration settle;

  @override
  State<SettledSize> createState() => _SettledSizeState();
}

class _SettledSizeState extends State<SettledSize> {
  Size? _settled;
  Size? _pending;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Size _sizeFor(Size available) {
    final settled = _settled;
    if (settled == null || settled.width != available.width || !available.height.isFinite) {
      _timer?.cancel();
      _pending = null;
      return _settled = available;
    }
    if (available != settled && available != _pending) {
      _pending = available;
      _timer?.cancel();
      _timer = Timer(widget.settle, () {
        if (mounted) setState(() => _settled = _pending);
      });
    } else if (available == settled) {
      _timer?.cancel();
      _pending = null;
    }
    return settled;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = _sizeFor(constraints.biggest);
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.bottomCenter,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: widget.child,
        ),
      );
    });
  }
}
