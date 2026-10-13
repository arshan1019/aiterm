import 'package:flutter/material.dart';
import '../app/theme.dart';

/// Text tabs with an accent underline that slides to the selected tab.
class TextTabs<T> extends StatefulWidget {
  const TextTabs({super.key, required this.tabs, required this.label, required this.selected, required this.onSelect});

  final List<T> tabs;
  final String Function(T tab) label;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  State<TextTabs<T>> createState() => _TextTabsState<T>();
}

class _TextTabsState<T> extends State<TextTabs<T>> {
  final _keys = <Object?, GlobalKey>{};

  GlobalKey _key(T t) => _keys.putIfAbsent(t, GlobalKey.new);
  final _rowKey = GlobalKey();
  Rect? _indicator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(TextTabs<T> old) {
    super.didUpdateWidget(old);
    // Labels can change width too ("changes 3").
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// Underline under the label's text, measured after layout.
  void _measure() {
    final row = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    final label = _key(widget.selected).currentContext?.findRenderObject() as RenderBox?;
    if (row == null || label == null || !mounted) return;
    final topLeft = label.localToGlobal(Offset.zero, ancestor: row);
    final rect = topLeft & label.size;
    if (rect != _indicator) setState(() => _indicator = rect);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final indicator = _indicator;
    return Container(
      height: 44,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Stack(
        key: _rowKey,
        children: [
          Row(
            children: [
              const SizedBox(width: 6),
              for (final t in widget.tabs)
                InkWell(
                  onTap: () => widget.onSelect(t),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: AnimatedDefaultTextStyle(
                      duration: Motion.standard,
                      curve: Motion.enter,
                      style: TextStyle(
                        color: t == widget.selected ? c.text : c.textMuted,
                        fontSize: 13,
                        fontWeight: t == widget.selected ? FontWeight.w600 : FontWeight.w400,
                        fontFamily: 'JetBrainsMono',
                      ),
                      child: Text(widget.label(t), key: _key(t)),
                    ),
                  ),
                ),
            ],
          ),
          if (indicator != null)
            AnimatedPositioned(
              duration: Motion.standard,
              curve: Motion.move,
              left: indicator.left,
              width: indicator.width,
              bottom: 0,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(1)),
              ),
            ),
        ],
      ),
    );
  }
}
