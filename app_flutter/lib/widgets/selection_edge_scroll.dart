import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Scrolls [controller] while a selection drag is held above or below this
/// widget, in place of Flutter's own selection autoscroller on that axis.
///
/// **Why not the framework's.** `EdgeDraggingAutoScroller._scroll` (used by
/// every `Scrollable` under a `SelectionArea`) awaits itself once per step of
/// at most 20 px, so a drag held past the edge builds a chain of futures one
/// level per step, and the release unwinds all of it in one microtask.
/// Measured in a profile build of the app (5k-line full-file view): fine at
/// ~500 steps, `StackOverflowError` at ~1500 -- about 50 s of holding. Flutter
/// master still recurses (checked 2026-11-10).
///
/// **How.** Every selection edge update passing through here has its vertical
/// coordinate clamped into this widget's box before it reaches the
/// scrollables below, so the vertical one never sees a point past its edge
/// and never starts its own autoscroll. While the real pointer is past the
/// edge, a [Ticker] moves [controller] each frame -- a loop, not a recursion
/// -- and re-sends the clamped update so the selection follows the content.
/// The speed is the framework's as it runs: the overshoot, capped at 20 px,
/// twenty times a second ([_stepsPerSecond]). The horizontal coordinate passes through untouched, so a sideways
/// scrollable below keeps its own autoscroll (one line's width deep).
class SelectionEdgeScroll extends StatefulWidget {
  const SelectionEdgeScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The vertical scrollable's controller, the one this widget's box frames.
  final ScrollController controller;

  final Widget child;

  @override
  State<SelectionEdgeScroll> createState() => _SelectionEdgeScrollState();
}

/// Steps a second, as the framework's scroller actually runs at 60 Hz. It
/// declares 30 (`_kDefaultSelectToScrollVelocityScalar`, a 33 ms animation a
/// step), but each step ends on a frame boundary and the next starts a frame
/// later: 50 ms a step, measured 415 px/s in the widget tier against a
/// nominal 600. This keeps the speed users already had.
const double _stepsPerSecond = 20;

/// The framework's `overDragMax`: the furthest one step moves.
const double _maxStep = 20;

class _SelectionEdgeScrollState extends State<SelectionEdgeScroll>
    with SingleTickerProviderStateMixin {
  late final _SelectionEdgeScrollDelegate _delegate =
      _SelectionEdgeScrollDelegate(this);
  late final Ticker _ticker = createTicker(_tick);

  /// The last edge update as the pointer made it, not clamped.
  SelectionEdgeUpdateEvent? _edge;
  Duration _lastTick = Duration.zero;

  /// True while [_tick] re-sends [_edge] through the delegate.
  bool _resending = false;

  @override
  void dispose() {
    _ticker.dispose();
    _delegate.dispose();
    super.dispose();
  }

  /// This widget's box in global coordinates, or null before layout.
  Rect? _box() {
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  /// How far [y] is past the box's top (negative) or bottom (positive).
  static double _overshoot(Rect box, double y) =>
      y < box.top ? y - box.top : (y > box.bottom ? y - box.bottom : 0);

  SelectionEdgeUpdateEvent _clamped(SelectionEdgeUpdateEvent event) {
    final Rect? box = _box();
    if (box == null || _overshoot(box, event.globalPosition.dy) == 0) {
      return event;
    }
    // Half a pixel inside, so the point lands on the last row drawn rather
    // than on the edge the framework's "past the edge" test starts at.
    final Offset at = Offset(
      event.globalPosition.dx,
      event.globalPosition.dy.clamp(box.top, box.bottom - 0.5),
    );
    return event.type == SelectionEventType.startEdgeUpdate
        ? SelectionEdgeUpdateEvent.forStart(
            globalPosition: at,
            granularity: event.granularity,
          )
        : SelectionEdgeUpdateEvent.forEnd(
            globalPosition: at,
            granularity: event.granularity,
          );
  }

  void _noteEdge(SelectionEdgeUpdateEvent event) {
    if (_resending) return;
    _edge = event;
    final Rect? box = _box();
    final bool past =
        box != null && _overshoot(box, event.globalPosition.dy) != 0;
    // Started only. A pointer back inside stops it on the next tick, which
    // finds no overshoot ([_tick]).
    if (past && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _stop() {
    if (_ticker.isActive) _ticker.stop();
  }

  void _tick(Duration elapsed) {
    final double seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final SelectionEdgeUpdateEvent? edge = _edge;
    final Rect? box = _box();
    if (edge == null || box == null || !widget.controller.hasClients) {
      _stop();
      return;
    }
    final double over = _overshoot(box, edge.globalPosition.dy);
    if (over == 0) {
      _stop();
      return;
    }
    final ScrollPosition position = widget.controller.position;
    final double step =
        math.min(over.abs(), _maxStep) * _stepsPerSecond * seconds;
    final double target = (position.pixels + over.sign * step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    position.jumpTo(target);
    // Already clamped, and not the pointer's own: [_noteEdge] would take the
    // inside point for the pointer having come back and stop.
    _resending = true;
    try {
      _delegate.dispatchSelectionEvent(_clamped(edge));
    } finally {
      _resending = false;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerUp: (_) => _stop(),
    onPointerCancel: (_) => _stop(),
    child: SelectionContainer(delegate: _delegate, child: widget.child),
  );
}

class _SelectionEdgeScrollDelegate extends StaticSelectionContainerDelegate {
  _SelectionEdgeScrollDelegate(this._owner);

  final _SelectionEdgeScrollState _owner;

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    _owner._noteEdge(event);
    return super.handleSelectionEdgeUpdate(_owner._clamped(event));
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    _owner._stop();
    return super.handleClearSelection(event);
  }
}
