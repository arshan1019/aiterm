import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The rows of a reversed chat list, kept steady while the newest ones grow.
///
/// Reading further up, the top row on screen stays exactly where it is:
/// the scroll offset is corrected during layout, in the same frame, so
/// nothing shows a frame late and a drag or fling carries on.
///
/// At the latest, the rows glide up instead of stepping up a line at a
/// time ([glide]).
class ChatSliver extends StatelessWidget {
  const ChatSliver({super.key, required this.delegate, required this.dragging, required this.glide});

  final SliverChildDelegate delegate;

  /// The user is dragging the list: it follows their finger, not the reply.
  final ValueGetter<bool> dragging;
  final bool glide;

  @override
  Widget build(BuildContext context) => _ChatAnchor(dragging: dragging, glide: glide, sliver: _ChatList(delegate: delegate));
}

class _ChatList extends SliverList {
  const _ChatList({required super.delegate});

  @override
  RenderSliverList createRenderObject(BuildContext context) =>
      _RenderChatList(childManager: context as SliverMultiBoxAdaptorElement);
}

class _RenderChatList extends RenderSliverList {
  _RenderChatList({required super.childManager});

  /// The rows' top edges, in scroll offsets (the list grows upward). Only
  /// the list may read its rows' sizes.
  final tops = <RenderBox, double>{};

  @override
  void performLayout() {
    super.performLayout();
    tops.clear();
    for (var box = firstChild; box != null; box = childAfter(box)) {
      if (childScrollOffset(box) case final at?) tops[box] = at + paintExtentOf(box);
    }
  }
}

class _ChatAnchor extends SingleChildRenderObjectWidget {
  const _ChatAnchor({required Widget sliver, required this.dragging, required this.glide}) : super(child: sliver);

  final ValueGetter<bool> dragging;
  final bool glide;

  @override
  RenderChatAnchor createRenderObject(BuildContext context) => RenderChatAnchor(dragging, glide);

  @override
  void updateRenderObject(BuildContext context, RenderChatAnchor renderObject) {
    renderObject
      ..dragging = dragging
      ..glide = glide;
  }
}

class RenderChatAnchor extends RenderProxySliver {
  RenderChatAnchor(this.dragging, this.glide);

  ValueGetter<bool> dragging;
  bool glide;

  /// How fast a glide settles: a line is mostly there within two of these.
  static const _settle = 0.07;

  RenderBox? _anchor;
  var _anchorTop = 0.0;

  /// How far the rows are painted below where they're laid out; falls to
  /// zero. Paint-only, so it costs what scrolling costs.
  var _lag = 0.0;
  Ticker? _ticker;
  var _lastTick = Duration.zero;

  _RenderChatList get _list => child! as _RenderChatList;

  void _layoutList() {
    final c = constraints;
    // The rows that the lag brings onto the screen are laid out too.
    _list.layout(
      c.copyWith(remainingPaintExtent: c.remainingPaintExtent + _lag, remainingCacheExtent: c.remainingCacheExtent + _lag),
      parentUsesSize: true,
    );
  }

  /// How far the anchor's top moved since the last layout (zero if it's gone).
  double _anchorMoved() {
    final top = _list.tops[_anchor];
    return top == null ? 0 : top - _anchorTop;
  }

  /// The anchor is the top row on screen.
  void _pickAnchor() {
    final edge = constraints.scrollOffset + constraints.remainingPaintExtent;
    _anchor = null;
    _anchorTop = 0;
    for (var box = _list.firstChild; box != null; box = _list.childAfter(box)) {
      final at = _list.childScrollOffset(box);
      if (at == null || at >= edge) break;
      _anchor = box;
      _anchorTop = _list.tops[box] ?? 0;
    }
  }

  @override
  void performLayout() {
    final c = constraints;
    _layoutList();
    // The list's own correction moves its rows along with the offset.
    if (_list.geometry!.scrollOffsetCorrection case final correction?) {
      _anchorTop += correction;
      geometry = _list.geometry;
      return;
    }
    final moved = _anchorMoved();
    if (moved.abs() > 0.01) {
      if (c.scrollOffset > 0 || dragging()) {
        // Never past the latest (when rows below shrank).
        final correction = math.max(moved, -c.scrollOffset);
        if (correction.abs() > 0.01) {
          _pickAnchor();
          geometry = SliverGeometry(scrollOffsetCorrection: correction);
          return;
        }
      } else if (glide && moved > 0 && moved < c.viewportMainAxisExtent) {
        _lag = math.min(_lag + moved, c.viewportMainAxisExtent / 2);
        _startTicking();
        _layoutList();
      }
    }
    _pickAnchor();
    final g = _list.geometry!;
    final paintData = _list.parentData! as SliverPhysicalParentData;
    if (_lag == 0) {
      paintData.paintOffset = Offset.zero;
      geometry = g;
      return;
    }
    final paintExtent = math.min(g.paintExtent, c.remainingPaintExtent);
    // A reversed list paints from its top, so what it laid out beyond this
    // sliver already pushes its rows down.
    paintData.paintOffset = Offset(0, _lag - (g.paintExtent - paintExtent));
    geometry = SliverGeometry(
      scrollExtent: g.scrollExtent,
      paintExtent: paintExtent,
      maxPaintExtent: g.maxPaintExtent,
      layoutExtent: math.min(g.layoutExtent, paintExtent),
      hitTestExtent: paintExtent,
      cacheExtent: math.min(g.cacheExtent, c.remainingCacheExtent),
      hasVisualOverflow: true,
    );
  }

  void _startTicking() {
    final ticker = _ticker ??= Ticker(_tick, debugLabel: 'ChatAnchor');
    if (ticker.isActive) return;
    _lastTick = Duration.zero;
    ticker.start();
  }

  void _tick(Duration elapsed) {
    final seconds = (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    _lag *= math.exp(-seconds / _settle);
    if (_lag < 0.5) {
      _lag = 0;
      _ticker?.stop();
    }
    markNeedsLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_list, offset + (_list.parentData! as SliverPhysicalParentData).paintOffset);
  }

  @override
  bool hitTestChildren(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    return super.hitTestChildren(result, mainAxisPosition: mainAxisPosition + _lag, crossAxisPosition: crossAxisPosition);
  }

  @override
  void detach() {
    _ticker?.dispose();
    _ticker = null;
    _lag = 0;
    _anchor = null;
    super.detach();
  }
}
