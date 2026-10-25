import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports [child]'s laid-out height to [onHeight] whenever it changes.
///
/// After the frame, never during layout: the listener resizes spacers,
/// which is a rebuild. `addPostFrameCallback` asks for no frame of its own,
/// so the report also asks for one ([FLU-postframe-no-frame]).
class SyncHeightReporter extends SingleChildRenderObjectWidget {
  const SyncHeightReporter({
    super.key,
    required this.onHeight,
    required super.child,
  });

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSyncHeightReporter(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSyncHeightReporter).onHeight = onHeight;
}

class _RenderSyncHeightReporter extends RenderProxyBox {
  _RenderSyncHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
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
