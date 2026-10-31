import 'package:flutter/widgets.dart';

import 'sync_scroll_controller.dart';
import 'sync_slot_heights.dart';

/// The end of [column]'s run in [segment]: empty, as tall as the segment's
/// tallest column less this one (Q2: 「只有 well 底色」, so it draws
/// nothing; the well behind it shows).
///
/// While built it is also where [scroll] reads this segment's end in this
/// column, to correct a follower against the leader.
class SyncSlotSpacer extends StatefulWidget {
  const SyncSlotSpacer({
    super.key,
    required this.heights,
    required this.column,
    required this.segment,
    this.scroll,
  });

  final SyncSlotHeights heights;
  final int column;
  final int segment;
  final SyncScrollController? scroll;

  @override
  State<SyncSlotSpacer> createState() => _SyncSlotSpacerState();
}

class _SyncSlotSpacerState extends State<SyncSlotSpacer> {
  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(SyncSlotSpacer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scroll, widget.scroll) ||
        oldWidget.column != widget.column ||
        oldWidget.segment != widget.segment) {
      oldWidget.scroll?.unregisterSpacer(
        oldWidget.column,
        oldWidget.segment,
        context,
      );
      _register();
    }
  }

  void _register() =>
      widget.scroll?.registerSpacer(widget.column, widget.segment, context);

  @override
  void dispose() {
    widget.scroll?.unregisterSpacer(widget.column, widget.segment, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.heights,
    builder: (BuildContext context, Widget? _) {
      final double h = widget.heights.spacerHeight(
        widget.column,
        widget.segment,
      );
      return SizedBox(height: h > 0 ? h : 0);
    },
  );
}
