import 'package:flutter/material.dart';

import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/split_pane.dart';

/// Spec page 19's shared management-panel template: 〈工具列 + 左清單 + 右明細〉,
/// the same shape as the Compare page (P12).
///
/// P19's whole point is that the twelve panels "只換欄位不換造型" — swap the
/// fields, keep the form — so this widget owns the form and each panel
/// supplies only [toolbar], [list] and [detail]. Adding a panel must not
/// mean inventing a layout; if a panel needs a shape this cannot express,
/// that is a spec question, not a reason to hand-roll a thirteenth design.
///
/// Presentational: no Riverpod, no FFI, no route awareness — same split as
/// `MenuBarRow`/`TabRow`, so a widget test can drive every state without a
/// repo session.
class GbmPanelTabShell extends StatelessWidget {
  const GbmPanelTabShell({
    super.key,
    required this.toolbar,
    required this.list,
    required this.detail,
    required this.storageId,
    this.emptyDetailMessage = 'Select an item to see its details',
    this.detailIsEmpty = false,
  });

  /// The panel's action buttons, laid out in a row above both columns.
  /// P19's `PANELSPEC` names these per panel (worktrees: Add / Prune / Open
  /// / Remove).
  final List<Widget> toolbar;

  /// Left column — the panel's items.
  final Widget list;

  /// Right column — the selected item's details.
  final Widget detail;

  /// Distinguishes this panel's splitter position in the persisted panel
  /// layout, so two different panels don't share one remembered width.
  final String storageId;

  /// Shown instead of [detail] when [detailIsEmpty]. Every panel has a
  /// "nothing selected yet" state, and spelling it out beats an empty pane
  /// that reads as a rendering bug.
  final String emptyDetailMessage;
  final bool detailIsEmpty;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      color: colors.surfaceApp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: GbmSpacing.space3,
              vertical: GbmSpacing.space2,
            ),
            decoration: BoxDecoration(
              color: colors.surfacePanel,
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Row(
              children: <Widget>[
                for (final (int index, Widget action) in toolbar.indexed) ...[
                  if (index > 0) const SizedBox(width: GbmSpacing.space2),
                  action,
                ],
              ],
            ),
          ),
          Expanded(
            child: GbmSplitPane(
              axis: Axis.horizontal,
              spec: GbmLayout.splitterPanelList,
              storageId: storageId,
              children: <Widget>[
                Container(color: colors.surfacePanel, child: list),
                if (detailIsEmpty)
                  Center(
                    child: Text(
                      emptyDetailMessage,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textTertiary,
                      ),
                    ),
                  )
                else
                  detail,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
