import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'sync_code_row_marker.dart';

/// Reports [child]'s laid-out height, and its lead -- the top of the first
/// [SyncCodeRowMarker] below it, or null without one (plan: Slice H) -- to
/// [onReport] whenever either changes, and again whenever [epoch] does.
///
/// After the frame, never during layout: the listener resizes spacers,
/// which is a rebuild. `addPostFrameCallback` asks for no frame of its own,
/// so the report also asks for one ([FLU-postframe-no-frame]).
class SyncHeightReporter extends SingleChildRenderObjectWidget {
  const SyncHeightReporter({
    super.key,
    required this.onReport,
    this.epoch,
    required super.child,
  });

  final void Function(double height, double? lead) onReport;

  /// What the heights are reported into. A new one starts from estimates,
  /// so it hears every height again: told only of changes, a `2 file`
  /// pane's rebuilt slot heights never learnt the rows already laid out,
  /// and the columns stayed off by the estimate's error (plan: Slice E).
  final Object? epoch;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSyncHeightReporter(onReport, epoch);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSyncHeightReporter)
        ..onReport = onReport
        ..epoch = epoch;
}

class _RenderSyncHeightReporter extends RenderProxyBox {
  _RenderSyncHeightReporter(this.onReport, this._epoch);

  void Function(double height, double? lead) onReport;

  Object? _epoch;
  set epoch(Object? value) {
    if (identical(value, _epoch)) return;
    _epoch = value;
    _reported = null;
    _reportedLead = null;
    markNeedsLayout();
  }

  double? _reported;
  double? _reportedLead;
  bool _scheduled = false;

  @override
  void performLayout() {
    super.performLayout();
    // A lead can move with the height unchanged (a one-shot block moving
    // within a card), so every layout is looked at after the frame.
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached || !hasSize) return;
      final double? lead = _lead();
      if (size.height == _reported && lead == _reportedLead) return;
      _reported = size.height;
      _reportedLead = lead;
      onReport(size.height, lead);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The first code row's top in this box, in paint order; null if none.
  double? _lead() {
    RenderSyncCodeRowMarker? first;
    void visit(RenderObject child) {
      if (first != null) return;
      if (child is RenderSyncCodeRowMarker) {
        first = child;
        return;
      }
      child.visitChildren(visit);
    }

    visitChildren(visit);
    final RenderSyncCodeRowMarker? marker = first;
    if (marker == null || !marker.hasSize) return null;
    return marker.localToGlobal(Offset.zero, ancestor: this).dy;
  }
}
