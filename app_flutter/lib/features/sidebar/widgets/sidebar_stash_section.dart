import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_availability.dart';
import '../../../actions/gbm_action_id.dart';
import '../../../data/models/stash_entry.dart';
import '../../../data/repositories/compare_tabs_repository.dart';
import '../../../data/repositories/panel_tabs_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import '../../../widgets/gbm_row.dart';
import '../../../widgets/prompt_text_dialog.dart';
import '../../history_graph/widgets/graph_date_format.dart';
import 'sidebar_section_label.dart';
import 'stash_menu_items.dart';

/// The sidebar's STASH section: its label and one row per stash.
///
/// Unlike `BranchSelectionActionBar` this is a `ConsumerStatefulWidget`
/// rather than a presentational one: a stash row's six actions (05-H) are
/// the only callers of the controller methods behind them, so routing them
/// back up through `SidebarPanel` as six callbacks would put a hop in the
/// way and leave the panel holding state it does not otherwise use, and
/// which stash row is selected is cosmetic, self-contained state with no
/// other reader. The branch tree is the opposite case on both counts: its
/// selection *is* panel state (other surfaces read it), which is why that
/// half stays there.
///
/// Renders nothing when [stashes] is empty, so the caller does not repeat the
/// P02-14 rule 5 emptiness check (「沒有命中的段落整段隱藏，不留空標題」).
class SidebarStashSection extends ConsumerStatefulWidget {
  const SidebarStashSection({
    super.key,
    required this.identity,
    required this.stashes,
  });

  final RepoIdentity identity;

  /// Already filtered by the caller -- P02-14's one box covers all three
  /// sections, and the 命中/總數 count is computed from the same list.
  final List<StashEntry> stashes;

  @override
  ConsumerState<SidebarStashSection> createState() =>
      _SidebarStashSectionState();
}

class _SidebarStashSectionState extends ConsumerState<SidebarStashSection> {
  // Purely cosmetic -- nothing downstream reads which stash is highlighted
  // (there's no detail pane here, unlike StashesPanel's own _selectedIndex,
  // which this mirrors). Keyed by index, matching StashesPanel's existing
  // convention for this exact model type rather than inventing a second
  // identity scheme for StashEntry selection.
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.stashes.isEmpty) return const SizedBox.shrink();

    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    // Sourced from isActionEnabled(), not session.conflictActive directly --
    // same pattern as every other conflict-sensitive gate in the sidebar.
    // branchStashChanges is the closest existing id (stash apply/pop mutate
    // the working tree/index the same way creating a stash would).
    final bool conflictActive = !isActionEnabled(
      GbmActionId.branchStashChanges,
      session,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SidebarSectionLabel('STASH'),
        for (final StashEntry stash in widget.stashes)
          _StashRow(
            stash: stash,
            selected: stash.index == _selectedIndex,
            onTap: () => setState(() => _selectedIndex = stash.index),
            onSecondaryTapDown: (TapDownDetails details) =>
                _openContextMenu(details.globalPosition, stash, conflictActive),
            onOpenMenu: (Offset position) =>
                _openContextMenu(position, stash, conflictActive),
          ),
      ],
    );
  }

  void _openContextMenu(
    Offset position,
    StashEntry stash,
    bool conflictActive,
  ) {
    showGbmContextMenu(
      context,
      position,
      stashMenuItems(
        onApply: conflictActive ? null : () => _apply(stash),
        onPop: conflictActive ? null : () => _apply(stash, pop: true),
        onCreateBranch: conflictActive ? null : () => _createBranchFrom(stash),
        onViewDiff: () => _viewDiff(stash),
        onCompare: () => _compare(stash),
        onDrop: () => _drop(stash),
      ),
    );
  }

  void _apply(StashEntry stash, {bool pop = false}) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .applyStash(stash.index, pop: pop);
  }

  Future<void> _createBranchFrom(StashEntry stash) async {
    final String? name = await promptText(
      context,
      title: 'New Branch from Stash',
      label: 'Branch name',
    );
    if (name == null || !context.mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .branchFromStash(stash.index, name);
  }

  /// 05-H "View diff" -- opens the Stashes panel with this stash selected.
  ///
  /// Was the manage-stashes *dialog* until Tier 6c moved that panel to a tab
  /// (spec page 14 `IAMAP`). `context.go`, not `push`: a panel is a tab
  /// beside History/Working Copy and replaces the shell's child. The stash
  /// index rides in the query rather than the tab id, so asking twice for
  /// two different stashes focuses one tab instead of opening two.
  void _viewDiff(StashEntry stash) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(panelTabsProvider(widget.identity).notifier)
        .open(GbmPanelKind.manageStashes);
    context.go(
      RoutePaths.panelFor(
        repoId,
        tabId,
        query: <String, String>{'select': '${stash.index}'},
      ),
    );
  }

  // Uses the stash's own commit oid as the Compare tab's left ref -- a
  // stash entry is a real commit (`git stash` creates one even though it
  // never gets a branch), so this is the same `left: <ref string>`
  // mechanism repositoryCompare already uses, not a new capability.
  void _compare(StashEntry stash) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(widget.identity).notifier)
        .open(left: stash.oid);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  void _drop(StashEntry stash) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .dropStash(stash.index);
  }
}

class _StashRow extends StatelessWidget {
  const _StashRow({
    required this.stash,
    required this.selected,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.onOpenMenu,
  });

  final StashEntry stash;
  final bool selected;
  final VoidCallback onTap;
  final GestureTapDownCallback onSecondaryTapDown;

  /// Called with the ⋯ button's own global position, for the same
  /// `showGbmContextMenu(context, position, items)` call `onSecondaryTapDown`
  /// makes -- one menu, two ways to reach it, mirroring BranchTreeItem.
  final ValueChanged<Offset> onOpenMenu;

  // Matches BranchTreeItem's `_kActionsSlotWidth`, for the same reason: a
  // fixed-width trailing slot keeps the sidebar's ⋯ column straight.
  static const double _kActionsSlotWidth = 32;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      // Two stacked lines (message + relative time) at textSm/textXs --
      // this is PanelListRow's own height for exactly this shape, chosen
      // because rowHeightComfortable alone clips a second line by ~2px.
      height: GbmSpacing.rowHeightComfortable + GbmSpacing.space3,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
      selected: selected,
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  stash.message,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatGraphDate(
                    DateTime.fromMillisecondsSinceEpoch(stash.timestamp * 1000),
                    DateTime.now(),
                  ),
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // Every row gets this button unconditionally, matching
          // BranchTreeItem -- the right-click menu above is real but
          // undiscoverable on its own.
          SizedBox(
            width: _kActionsSlotWidth,
            child: Builder(
              builder: (BuildContext buttonContext) => IconButton(
                tooltip: 'Stash actions',
                icon: Icon(
                  Icons.more_vert,
                  size: 16,
                  color: colors.textTertiary,
                ),
                iconSize: 16,
                constraints: const BoxConstraints(
                  minWidth: _kActionsSlotWidth,
                  minHeight: _kActionsSlotWidth,
                ),
                padding: EdgeInsets.zero,
                onPressed: () {
                  final RenderBox box =
                      buttonContext.findRenderObject()! as RenderBox;
                  onOpenMenu(box.localToGlobal(Offset.zero));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
