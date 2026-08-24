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
import '../../../widgets/prompt_text_dialog.dart';
import 'sidebar_section_label.dart';
import 'stash_menu_items.dart';

/// The sidebar's STASH section: its label and one row per stash.
///
/// Unlike `BranchSelectionActionBar` this is a `ConsumerWidget` rather than a
/// presentational one, because a stash row's six actions (05-H) are the only
/// callers of the controller methods behind them -- routing them back up
/// through `SidebarPanel` as six callbacks would put a hop in the way and
/// leave the panel holding state it does not otherwise use. The branch tree
/// is the opposite case: its selection *is* panel state, which is why that
/// half stays there.
///
/// Renders nothing when [stashes] is empty, so the caller does not repeat the
/// P02-14 rule 5 emptiness check (「沒有命中的段落整段隱藏，不留空標題」).
class SidebarStashSection extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    if (stashes.isEmpty) return const SizedBox.shrink();

    final RepoSessionState session = ref.watch(repoSessionProvider(identity));
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
        for (final StashEntry stash in stashes)
          _StashRow(
            stash: stash,
            onSecondaryTapDown: (TapDownDetails details) =>
                _openContextMenu(context, ref, details, stash, conflictActive),
          ),
      ],
    );
  }

  void _openContextMenu(
    BuildContext context,
    WidgetRef ref,
    TapDownDetails details,
    StashEntry stash,
    bool conflictActive,
  ) {
    showGbmContextMenu(
      context,
      details.globalPosition,
      stashMenuItems(
        onApply: conflictActive ? null : () => _apply(ref, stash),
        onPop: conflictActive ? null : () => _apply(ref, stash, pop: true),
        onCreateBranch: conflictActive
            ? null
            : () => _createBranchFrom(context, ref, stash),
        onViewDiff: () => _viewDiff(context, ref, stash),
        onCompare: () => _compare(context, ref, stash),
        onDrop: () => _drop(ref, stash),
      ),
    );
  }

  void _apply(WidgetRef ref, StashEntry stash, {bool pop = false}) {
    ref
        .read(repoSessionProvider(identity).notifier)
        .applyStash(stash.index, pop: pop);
  }

  Future<void> _createBranchFrom(
    BuildContext context,
    WidgetRef ref,
    StashEntry stash,
  ) async {
    final String? name = await promptText(
      context,
      title: 'New Branch from Stash',
      label: 'Branch name',
    );
    if (name == null || !context.mounted) return;
    ref
        .read(repoSessionProvider(identity).notifier)
        .branchFromStash(stash.index, name);
  }

  /// 05-H "View diff" -- opens the Stashes panel with this stash selected.
  ///
  /// Was the manage-stashes *dialog* until Tier 6c moved that panel to a tab
  /// (spec page 14 `IAMAP`). `context.go`, not `push`: a panel is a tab
  /// beside History/Working Copy and replaces the shell's child. The stash
  /// index rides in the query rather than the tab id, so asking twice for
  /// two different stashes focuses one tab instead of opening two.
  void _viewDiff(BuildContext context, WidgetRef ref, StashEntry stash) {
    final String repoId = Uri.encodeComponent(identity.workDir);
    final String tabId = ref
        .read(panelTabsProvider(identity).notifier)
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
  void _compare(BuildContext context, WidgetRef ref, StashEntry stash) {
    final String repoId = Uri.encodeComponent(identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(identity).notifier)
        .open(left: stash.oid);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  void _drop(WidgetRef ref, StashEntry stash) {
    ref.read(repoSessionProvider(identity).notifier).dropStash(stash.index);
  }
}

class _StashRow extends StatelessWidget {
  const _StashRow({required this.stash, required this.onSecondaryTapDown});

  final StashEntry stash;
  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        // No fixed height, unlike a branch row -- this row shows two lines
        // (message + relative time) rather than one, and rowHeightCompact
        // (26px) is too short for both at GbmTypography's textSm/textXs
        // sizes, overflowing the Column below by several pixels. Vertical
        // padding gives it breathing room instead of pinning a height that
        // would need recalibrating by hand every time either text style
        // changes.
        padding: const EdgeInsets.symmetric(
          horizontal: GbmSpacing.space2,
          vertical: GbmSpacing.space1,
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: GbmSpacing.space2),
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
                    _relativeTime(stash.timestamp),
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _relativeTime(int millisecondsSinceEpoch) {
    final Duration diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch),
    );
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
