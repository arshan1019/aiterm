import 'package:flutter/widgets.dart';
import '../app/theme.dart';

/// An [IndexedStack] that fades the newly shown child in (with an optional
/// small rise). Every child stays mounted, so terminals keep running and
/// lists keep their scroll position.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = Motion.standard,
    this.rise = 0,
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  /// Pixels the incoming child rises by while fading in.
  final double rise;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: widget.duration, value: 1);
  late final _fade = CurvedAnimation(parent: _controller, curve: Motion.enter);

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          // The same wrapper for every child, active or not, so switching
          // never changes the tree shape (which would remount the child).
          _Reveal(
            animation: i == widget.index ? _fade : kAlwaysCompleteAnimation,
            rise: widget.rise,
            child: widget.children[i],
          ),
      ],
    );
  }
}

class _Reveal extends AnimatedWidget {
  const _Reveal({required Animation<double> animation, required this.rise, required this.child})
      : super(listenable: animation);

  final double rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Opacity(
      opacity: t,
      child: rise == 0 ? child : Transform.translate(offset: Offset(0, rise * (1 - t)), child: child),
    );
  }
}
