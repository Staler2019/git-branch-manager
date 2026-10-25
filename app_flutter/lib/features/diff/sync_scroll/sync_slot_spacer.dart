import 'package:flutter/widgets.dart';

import 'sync_slot_heights.dart';

/// The end of [column]'s run in [segment]: empty, as tall as the segment's
/// tallest column less this one (Q2: 「只有 well 底色」, so it draws
/// nothing; the well behind it shows).
class SyncSlotSpacer extends StatelessWidget {
  const SyncSlotSpacer({
    super.key,
    required this.heights,
    required this.column,
    required this.segment,
  });

  final SyncSlotHeights heights;
  final int column;
  final int segment;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: heights,
    builder: (BuildContext context, Widget? _) {
      final double h = heights.spacerHeight(column, segment);
      return SizedBox(height: h > 0 ? h : 0);
    },
  );
}
