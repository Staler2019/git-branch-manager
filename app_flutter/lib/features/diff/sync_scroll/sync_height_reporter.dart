import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports [child]'s laid-out height to [onHeight] whenever it changes,
/// and again whenever [epoch] does.
///
/// After the frame, never during layout: the listener resizes spacers,
/// which is a rebuild. `addPostFrameCallback` asks for no frame of its own,
/// so the report also asks for one ([FLU-postframe-no-frame]).
class SyncHeightReporter extends SingleChildRenderObjectWidget {
  const SyncHeightReporter({
    super.key,
    required this.onHeight,
    this.epoch,
    required super.child,
  });

  final ValueChanged<double> onHeight;

  /// What the heights are reported into. A new one starts from estimates,
  /// so it hears every height again: told only of changes, a `2 file`
  /// pane's rebuilt slot heights never learnt the rows already laid out,
  /// and the columns stayed off by the estimate's error (plan: Slice E).
  final Object? epoch;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSyncHeightReporter(onHeight, epoch);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSyncHeightReporter)
        ..onHeight = onHeight
        ..epoch = epoch;
}

class _RenderSyncHeightReporter extends RenderProxyBox {
  _RenderSyncHeightReporter(this.onHeight, this._epoch);

  ValueChanged<double> onHeight;

  Object? _epoch;
  set epoch(Object? value) {
    if (identical(value, _epoch)) return;
    _epoch = value;
    _reported = null;
    markNeedsLayout();
  }

  double? _reported;
  bool _scheduled = false;

  @override
  void performLayout() {
    super.performLayout();
    if (size.height == _reported || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached || !hasSize || size.height == _reported) return;
      _reported = size.height;
      onHeight(size.height);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}
