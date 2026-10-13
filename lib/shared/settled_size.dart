import 'dart:async';
import 'package:flutter/widgets.dart';

/// Where a terminal's content sits while the keyboard animates, relative to
/// its settled layout, so the animation ends exactly where xterm's resize
/// puts things (no jump):
///
/// * less room: content moves up only as far as needed to keep the cursor
///   row visible (xterm keeps the cursor on screen and drops blank rows);
/// * more room: content moves down by as many rows as scrollback can fill
///   (xterm pulls scrollback back in; with none, it adds blank rows below).
///
/// Whole rows only, like the real resize. Negative is up.
double keyboardOffset({
  required double settledHeight,
  required double availableHeight,
  required double lineHeight,
  required int cursorRow,
  required int scrollbackLines,
}) {
  final settledRows = (settledHeight / lineHeight).floor();
  final rows = (availableHeight / lineHeight).floor();
  if (rows < settledRows) {
    final shift = cursorRow + 1 - rows;
    return shift > 0 ? -shift * lineHeight : 0;
  }
  if (rows > settledRows) {
    final pulled = rows - settledRows < scrollbackLines ? rows - settledRows : scrollbackLines;
    return pulled * lineHeight;
  }
  return 0;
}

/// Lays [child] out at the last *settled* size.
///
/// While the available height keeps changing (the keyboard sliding in or
/// out resizes the body every frame) the child keeps its previous size and
/// is shifted by [offsetFor] and clipped. Once changes stop for [settle],
/// the child takes the new size in a single layout. For the terminal that
/// means one reflow per keyboard change instead of one per frame, with the
/// content moving the way the final resize will leave it.
///
/// Width changes (rotation, split screen) apply immediately.
class SettledSize extends StatefulWidget {
  const SettledSize({
    super.key,
    required this.child,
    this.offsetFor,
    this.settle = const Duration(milliseconds: 90),
  });

  final Widget child;
  final Duration settle;

  /// Vertical shift of the child while its size lags the available height
  /// (settled height, available height). Without it the child stays at the top.
  final double Function(double settledHeight, double availableHeight)? offsetFor;

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
      final available = constraints.biggest;
      final size = _sizeFor(available);
      final dy = size.height == available.height ? 0.0 : widget.offsetFor?.call(size.height, available.height) ?? 0.0;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: Transform.translate(offset: Offset(0, dy), child: widget.child),
        ),
      );
    });
  }
}
