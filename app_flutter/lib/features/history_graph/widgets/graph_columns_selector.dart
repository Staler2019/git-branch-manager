import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/graph_column.dart';
import '../../../data/repositories/graph_columns_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/lucide_icon.dart';

/// The picker's own width. Spec's grid column for this panel is 214px
/// (`spec_raw.html:1351`); the extra 6 are the panel padding it sits inside.
const double kGraphColumnsSelectorWidth = 220;

/// Spec page 02 item 16's column picker, drawn as the mockup draws it
/// (`spec_raw.html:1354-1362`): a `.gbm-menu` panel whose rows are a 12px
/// check box, the label, and a right-side hint.
///
/// Every piece of state lives in a notifier, not in this widget --
/// [graphColumnVisibilityProvider] for the check boxes and
/// [graphColumnOrderProvider] for the drag order. An earlier version kept
/// visibility in local `State` and wrote through to SharedPreferences: that
/// fixed the check box not reflecting its own taps, but left the setting
/// invisible to the commit list, which never read it back. Sitting both on
/// one notifier is what makes a toggle reach the rows.
///
/// One deliberate departure from the plan that produced this widget: the drag
/// affordance is a grip glyph in the row's trailing hint slot, not the
/// framework's `buildDefaultDragHandles`. That default is a 24px Material
/// `Icons.drag_handle` stacked over a 24px row, and it is gated on
/// `Theme.of(context).platform` -- so a widget test (android) would exercise
/// the long-press path no desktop user ever gets.
///
/// **The whole row must not be the handle**, which an earlier version of this
/// file made it. `ReorderableDragStartListener` hands the pointer to an
/// `ImmediateMultiDragGestureRecognizer`, whose acceptance threshold is
/// `computeHitSlop(kind)` -- and that is `kPrecisePointerHitSlop` (**1px**)
/// for `PointerDeviceKind.mouse`, not `kTouchSlop` (18px). Measured on this
/// widget: a mouse click with 2px of travel lost its toggle outright, where
/// the same gesture as touch still toggled. On a desktop app that is the
/// primary input device, so the drag surface has to be somewhere the user is
/// not trying to click. See `graph_columns_selector_test.dart`'s
/// "a wobbly mouse click still toggles" for the regression lock.
class GraphColumnsSelector extends ConsumerWidget {
  const GraphColumnsSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final List<GbmGraphColumnId> order = ref.watch(graphColumnOrderProvider);
    final Map<String, bool> visibility = ref.watch(
      graphColumnVisibilityProvider,
    );

    // resolveGraphColumnOrder() always emits the locked columns first, so
    // splitting on isMovable also splits on position -- which is what lets
    // the index conversion below be a constant offset.
    final List<GbmGraphColumnId> locked = <GbmGraphColumnId>[
      for (final GbmGraphColumnId id in order)
        if (!id.isMovable) id,
    ];
    final List<GbmGraphColumnId> movable = <GbmGraphColumnId>[
      for (final GbmGraphColumnId id in order)
        if (id.isMovable) id,
    ];

    return SizedBox(
      width: kGraphColumnsSelectorWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(GbmSpacing.space2, 3, 0, 5),
            child: Text(
              'Columns',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.05 * 9.5,
                color: colors.textTertiary,
              ),
            ),
          ),
          for (final GbmGraphColumnId id in locked)
            _ColumnRow(id: id, isVisible: true),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: movable.length,
            // onReorderItem, not onReorder: it hands back a newIndex already
            // adjusted for the removed item, matching move()'s own
            // insert-after-removal semantics, so no off-by-one belongs here.
            //
            // The `+ locked.length` is the other half of the conversion, and
            // it is not cosmetic: these indices address only the movable
            // rows, while move() addresses the full order. Without it a drag
            // of the first row would arrive as `move(0, …)`, land on `graph`,
            // and be refused as a locked slot -- a silent no-op.
            onReorderItem: (int oldIndex, int newIndex) {
              ref
                  .read(graphColumnOrderProvider.notifier)
                  .move(oldIndex + locked.length, newIndex + locked.length);
            },
            itemBuilder: (BuildContext context, int i) {
              final GbmGraphColumnId id = movable[i];
              final bool isVisible = isGraphColumnVisible(
                visibility,
                id.storageId,
              );
              return _ColumnRow(
                key: ValueKey<String>(id.storageId),
                id: id,
                isVisible: isVisible,
                onToggle: () => ref
                    .read(graphColumnVisibilityProvider.notifier)
                    .setVisible(id.storageId, !isVisible),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: const _GripHandle(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One `.gbm-menu-item` row: check box, label, hint.
///
/// A locked column passes no [onToggle] -- that, rather than a separate
/// `locked` flag, is what dims the row and prints the `固定` hint, so the two
/// cannot disagree about which rows are pinned. It also passes no [trailing],
/// so the hint slot holds either `固定` or a drag handle and never both.
class _ColumnRow extends StatelessWidget {
  const _ColumnRow({
    super.key,
    required this.id,
    required this.isVisible,
    this.onToggle,
    this.trailing,
  });

  final GbmGraphColumnId id;
  final bool isVisible;
  final VoidCallback? onToggle;

  /// The drag handle, for a movable row. Built by the list so the reorder
  /// index stays with the list rather than leaking into this row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool isLocked = onToggle == null;

    return Opacity(
      // Spec's `opacity: .5` for a locked row (`spec_raw.html:1357`).
      opacity: isLocked ? 0.5 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
          child: SizedBox(
            height: 24,
            child: Row(
              children: <Widget>[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    // On: filled accent. Off: an outline over the panel
                    // surface. Spec draws both with a 1.5px border, so the
                    // box keeps the same footprint either way.
                    color: isVisible ? colors.accent : colors.surfacePanel,
                    border: Border.all(
                      color: isVisible ? colors.accent : colors.borderStrong,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                Expanded(
                  child: Text(
                    // The label lives on the enum, so the picker and any
                    // other reader cannot spell a column two ways. The map
                    // this replaced had drifted from spec on two of eight
                    // ("Hash", "Changed Files").
                    id.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (isLocked)
                  Text(
                    '固定',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colors.textTertiary,
                    ),
                  )
                else
                  ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The drag surface of a movable row: a Lucide `grip-vertical` in the slot
/// the locked rows use for their `固定` hint.
///
/// The `Container`'s transparent colour is load-bearing, not decoration --
/// `ReorderableDragStartListener` is a `Listener`, which defers hit testing to
/// its child, so without it only the glyph's own painted pixels would start a
/// drag. `Container(color:)` builds a `ColoredBox` whose render object is
/// constructed `HitTestBehavior.opaque`, which is what makes the whole 20x24
/// box grabbable.
class _GripHandle extends StatelessWidget {
  const _GripHandle();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Container(
        width: 20,
        height: 24,
        alignment: Alignment.center,
        color: Colors.transparent,
        child: LucideIcon(
          'grip-vertical',
          size: 12,
          color: context.gbmColors.textTertiary,
        ),
      ),
    );
  }
}

/// Opens the picker under [anchor] (a global-coordinate rect, normally the
/// History header button's), right-aligned to it because that button sits at
/// the panel's trailing edge.
///
/// `showGeneralDialog` rather than `showGbmMenu`: a menu closes on the first
/// click, and this panel exists to be clicked repeatedly -- eight check boxes
/// and a drag. Copied from `showRepoSwitcherPopover`, which needed the same
/// thing for its search field. The transparent barrier keeps click-outside
/// and Esc dismissal without dimming the window behind it.
Future<void> showGraphColumnsPopover(
  BuildContext context, {
  required Rect anchor,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    pageBuilder: (BuildContext dialogContext, _, _) =>
        _GraphColumnsPopover(anchor: anchor),
  );
}

/// Roughly how tall the picker is at its full eight rows -- header, eight
/// 24px rows, the panel's own padding and border.
///
/// Used only to decide whether the popover opens below its anchor or above
/// it. An estimate is enough, and measuring would need a layout pass that
/// has to happen *after* the placement it would inform: being wrong in
/// either direction costs at most a scroll, since the panel sits in a
/// SingleChildScrollView whichever way it opens.
const double _kEstimatedPopoverHeight = 8 * 24 + 26 + 10 + 2;

class _GraphColumnsPopover extends StatelessWidget {
  const _GraphColumnsPopover({required this.anchor});

  final Rect anchor;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Size screen = MediaQuery.sizeOf(context);
    // Right-aligned to the anchor, then clamped so a button near either edge
    // still lands the panel fully on screen.
    final double left = math.max(
      GbmSpacing.space2,
      math.min(
        anchor.right - kGraphColumnsSelectorWidth,
        screen.width - kGraphColumnsSelectorWidth - GbmSpacing.space2,
      ),
    );
    // Opens above the anchor when there is not room below it and there is
    // more room above. Measured, not assumed: the History header button sits
    // near the *bottom* of the window in the default layout (y ~= 681 of 900
    // on a 1440x900 desktop), which left the panel 175px for its ~230px of
    // rows -- so Committer and Changed files rendered inside a scroll view
    // the user had to find before they could tick them. A popover is not a
    // dropdown; it belongs on whichever side it fits.
    final double gap = GbmSpacing.space1;
    final double margin = GbmSpacing.space3;
    final double spaceBelow = screen.height - anchor.bottom - gap - margin;
    final double spaceAbove = anchor.top - gap - margin;
    final bool openAbove =
        spaceBelow < _kEstimatedPopoverHeight && spaceAbove > spaceBelow;
    final double available = math.max(120, openAbove ? spaceAbove : spaceBelow);

    return Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: openAbove ? null : anchor.bottom + gap,
          bottom: openAbove ? screen.height - anchor.top + gap : null,
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: available),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: colors.surfaceOverlay,
                  border: Border.all(color: colors.borderDefault),
                  borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
                  boxShadow: GbmEffects.shadowLg(context.gbmThemeVariant),
                ),
                child: const SingleChildScrollView(
                  child: GraphColumnsSelector(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
