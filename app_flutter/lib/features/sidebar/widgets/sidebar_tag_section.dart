import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_availability.dart';
import '../../../actions/gbm_action_id.dart';
import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/branch_repository.dart';
import '../../../data/repositories/compare_tabs_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/tokens.dart';
import 'branch_tree_item.dart';
import 'sidebar_section_label.dart';

/// The sidebar's TAGS section: its label and one `BranchTreeItem` per tag.
///
/// A `ConsumerWidget` for the same reason as [SidebarStashSection]: the four
/// tag actions are the only callers of the controller methods behind them,
/// so routing them up through `SidebarPanel` would add a hop and leave the
/// panel holding state it does not otherwise use.
///
/// Renders nothing when [tags] is empty, so the caller does not repeat the
/// P02-14 rule 5 emptiness check.
class SidebarTagSection extends ConsumerWidget {
  const SidebarTagSection({
    super.key,
    required this.identity,
    required this.tags,
  });

  final RepoIdentity identity;

  /// Already filtered by the caller -- P02-14's one box covers all three
  /// sections, and the 命中/總數 count is computed from the same list.
  final List<RefInfo> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tags.isEmpty) return const SizedBox.shrink();

    final RepoSessionState session = ref.watch(repoSessionProvider(identity));
    // Sourced from isActionEnabled(), not session.conflictActive directly --
    // single source of truth for checkout availability.
    final bool conflictActive = !isActionEnabled(
      GbmActionId.branchCheckout,
      session,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SidebarSectionLabel('TAGS'),
        for (final RefInfo tag in tags)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space1),
            child: BranchTreeItem(
              ref: tag,
              onCheckout: () =>
                  checkoutBranch(ref, identity, tag.shortName, detach: true),
              // Only offered when the choice is unambiguous: `gbm_push_tag`
              // targets exactly one remote per call.
              onPushTag: session.remotes.length == 1
                  ? () => ref
                        .read(repoSessionProvider(identity).notifier)
                        .pushTag(
                          session.remotes.single.name,
                          name: tag.shortName,
                        )
                  : null,
              onCompareRef: () => _compare(context, ref, tag),
              onDeleteTag: () => ref
                  .read(repoSessionProvider(identity).notifier)
                  .deleteTag(tag.shortName),
              conflictActive: conflictActive,
            ),
          ),
      ],
    );
  }

  // Same `left: <ref string>` mechanism as the stash section's compare -- a
  // tag name is already a valid ref on its own.
  void _compare(BuildContext context, WidgetRef ref, RefInfo tag) {
    final String repoId = Uri.encodeComponent(identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(identity).notifier)
        .open(left: tag.shortName);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }
}
