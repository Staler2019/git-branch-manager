import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ref_snapshot.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import 'widgets/branch_tree_item.dart';

/// Local branches for the open repository, with checkout-on-tap. The Dart
/// analog of `SidebarPanel`/`RefTreeModel` (src/app/views/SidebarPanel.cpp,
/// src/app/models/RefTreeModel.cpp) -- local branches only for M1; remote
/// branches/tags/stashes/worktrees join once their capi domains exist
/// (M3/M5, see the plan's milestone roadmap).
class SidebarPanel extends ConsumerWidget {
  const SidebarPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RefSnapshot refs = ref.watch(repoRefsProvider(identity));
    final GbmColors colors = context.gbmColors;
    final List<RefInfo> branches = refs.localBranches;

    return Container(
      width: 240,
      decoration: BoxDecoration(color: colors.surfacePanel, border: Border(right: BorderSide(color: colors.borderSubtle))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(GbmSpacing.space3, GbmSpacing.space3, GbmSpacing.space3, GbmSpacing.space1),
            child: Text(
              'BRANCHES',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontWeight: GbmTypography.weightSemibold,
                color: colors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: branches.isEmpty
                ? Center(child: Text('No branches', style: TextStyle(color: colors.textTertiary, fontSize: GbmTypography.textSm)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space1),
                    itemCount: branches.length,
                    itemBuilder: (context, index) {
                      final RefInfo branch = branches[index];
                      return BranchTreeItem(
                        ref: branch,
                        onCheckout: () => checkoutBranch(ref, identity, branch.shortName),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
