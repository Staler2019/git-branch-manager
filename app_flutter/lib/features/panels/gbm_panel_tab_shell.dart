import 'package:flutter/material.dart';

import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/split_pane.dart';
import 'panel_toolbar_spec.dart';

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
    this.toolbar,
    this.toolbarSpec,
    required this.list,
    required this.detail,
    required this.storageId,
    this.detailActions,
    this.banner,
    this.listHeader,
    this.statusBar,
    this.emptyDetailMessage = 'Select an item to see its details',
    this.detailIsEmpty = false,
  }) : assert(
         (toolbar == null) != (toolbarSpec == null),
         'supply exactly one of toolbar (the flat pre-P19 list) or '
         'toolbarSpec (rule 2\'s four segments). The flat form is being '
         'retired one panel at a time and is deleted once all twelve have '
         'migrated.',
       );

  /// The panel's action buttons as one flat row — the shape that predates
  /// P19 樣板規則 2 being audited.
  ///
  /// **Being retired.** Exactly one of this and [toolbarSpec] is supplied;
  /// panels migrate one at a time, and the final commit of that migration
  /// deletes this parameter, which is what turns rule 2's four segments from
  /// available into mandatory.
  final List<Widget>? toolbar;

  /// Rule 2's four segments plus the pinned filter. See [PanelToolbarSpec].
  final PanelToolbarSpec? toolbarSpec;

  /// Left column — the panel's items.
  final Widget list;

  /// Right column — the selected item's details.
  final Widget detail;

  /// P19 樣板規則 4: 「動作列在明細底部，danger 靠右」. Normally a
  /// [PanelDetailActions]. Pinned below [detail] rather than appended inside
  /// it, so a long field list scrolls underneath it instead of carrying it
  /// off the bottom of the pane.
  ///
  /// Optional because it is conditional, not because it is decoration: a
  /// panel whose selected item affords no action has nothing to put here.
  /// Not drawn at all when [detailIsEmpty] — an action row with no subject
  /// would act on nothing.
  final Widget? detailActions;

  /// P19 樣板規則 5: 「例外狀態用面板內 banner，不用 dialog、不用 toast」.
  /// Normally a [GbmWarningBanner]. Spans the whole panel, below the toolbar
  /// and above both columns, because the exception is the panel's, not one
  /// column's.
  ///
  /// Optional in the strong sense: rule 5 says what an exception state looks
  /// like, so a panel with no exception has nothing to draw here.
  final Widget? banner;

  /// P19's list-column header — the mockup's 「Worktrees · 4」. Sits inside
  /// the left column above [list] and does not scroll with it.
  ///
  /// The count here and the one in [statusBar] must come from a single
  /// computed value; two counts of the same collection are two things that
  /// can disagree.
  final Widget? listHeader;

  /// P19 樣板規則 6: 「狀態列一律寫實際數量與耗時」. Spans the panel's
  /// bottom edge.
  ///
  /// The shell only places it — each panel supplies the text, because only
  /// the panel knows which refresh it is timing. Where a panel has no
  /// measurable duration, it writes the count and says so rather than
  /// printing `0 ms`.
  final Widget? statusBar;

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
          if (toolbarSpec != null)
            PanelToolbarRow(spec: toolbarSpec!)
          else
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
                  for (final (int i, Widget action) in toolbar!.indexed) ...[
                    if (i > 0) const SizedBox(width: GbmSpacing.space2),
                    action,
                  ],
                ],
              ),
            ),
          ?banner,
          Expanded(
            child: GbmSplitPane(
              axis: Axis.horizontal,
              spec: GbmLayout.splitterPanelList,
              storageId: storageId,
              children: <Widget>[
                Container(
                  color: colors.surfacePanel,
                  child: listHeader == null
                      ? list
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            listHeader!,
                            Expanded(child: list),
                          ],
                        ),
                ),
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
                else if (detailActions == null)
                  detail
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: detail),
                      detailActions!,
                    ],
                  ),
              ],
            ),
          ),
          ?statusBar,
        ],
      ),
    );
  }
}
