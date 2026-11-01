import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks [child] as a code row, so the [SyncHeightReporter] above it can
/// find the first one and report how far down its item it starts -- the
/// item's lead (plan: Slice H). Lays out and paints as [child] alone.
class SyncCodeRowMarker extends SingleChildRenderObjectWidget {
  const SyncCodeRowMarker({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSyncCodeRowMarker();
}

/// [SyncCodeRowMarker]'s render object; only its type is read.
class RenderSyncCodeRowMarker extends RenderProxyBox {}
