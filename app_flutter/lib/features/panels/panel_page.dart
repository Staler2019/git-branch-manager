import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/panel_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import 'bisect_panel.dart';
import 'blame_panel.dart';
import 'file_history_panel.dart';
import 'interactive_rebase_panel.dart';
import 'line_history_panel.dart';
import 'patches_panel.dart';
import 'lfs_panel.dart';
import 'reflog_panel.dart';
import 'remotes_panel.dart';
import 'stashes_panel.dart';
import 'submodules_panel.dart';
import 'worktrees_panel.dart';

/// Renders whichever management panel `/repo/:repoId/panel/:tabId` names --
/// the tab-strip counterpart of `ComparePage`, resolving the id against
/// [panelTabsProvider] the same way `ComparePage` resolves against
/// `compareTabsProvider`.
///
/// Spec page 14's `IAMAP` assigns twelve panels to this carrier and all
/// twelve have landed, so the switch is exhaustive over [GbmPanelKind] with
/// no default arm — adding a thirteenth kind is a compile error here rather
/// than a blank pane at runtime.
class PanelPage extends ConsumerWidget {
  const PanelPage({
    super.key,
    required this.identity,
    required this.tabId,
    this.query = const <String, String>{},
  });

  final RepoIdentity identity;
  final String tabId;

  /// The route's query parameters, carrying per-panel opening state (see
  /// [RoutePaths.panelFor]). Panels that need none ignore it.
  final Map<String, String> query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<PanelTabSpec> tabs = ref.watch(panelTabsProvider(identity));
    final PanelTabSpec? spec = tabs
        .where((PanelTabSpec t) => t.id == tabId)
        .firstOrNull;

    // A closed tab's route can still be the current location for one frame
    // (close-then-navigate), and a hot restart drops the provider while the
    // router keeps the URL -- neither should throw.
    if (spec == null) {
      return const _PanelMessage(message: 'This panel is no longer open');
    }

    return switch (spec.kind) {
      GbmPanelKind.manageWorktrees => WorktreesPanel(identity: identity),
      GbmPanelKind.manageStashes => StashesPanel(
        identity: identity,
        initialSelectedIndex: int.tryParse(query['select'] ?? ''),
      ),
      GbmPanelKind.manageRemotes => RemotesPanel(identity: identity),
      GbmPanelKind.manageSubmodules => SubmodulesPanel(identity: identity),
      GbmPanelKind.manageLfs => LfsPanel(identity: identity),
      GbmPanelKind.reflog => ReflogPanel(identity: identity),
      GbmPanelKind.bisect => BisectPanel(identity: identity),
      // The three per-subject panels are always about a file. A tab
      // without one cannot exist (panelTabsProvider.open requires the
      // subject for these kinds), so `?? ''` is unreachable rather than a
      // fallback -- an empty path would ask git to blame the whole repo.
      GbmPanelKind.blame => BlamePanel(
        identity: identity,
        path: spec.subject ?? '',
      ),
      GbmPanelKind.fileHistory => FileHistoryPanel(
        identity: identity,
        path: spec.subject ?? '',
      ),
      GbmPanelKind.lineHistory => LineHistoryPanel(
        identity: identity,
        path: spec.subject ?? '',
        initialStartLine: int.tryParse(query['from'] ?? '') ?? 1,
        initialEndLine: int.tryParse(query['to'] ?? '') ?? 1,
      ),
      GbmPanelKind.interactiveRebase => InteractiveRebasePanel(
        identity: identity,
      ),
      GbmPanelKind.patches => PatchesPanel(identity: identity),
    };
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      color: colors.surfaceApp,
      alignment: Alignment.center,
      child: Text(
        message,
        style: TextStyle(
          fontSize: GbmTypography.textSm,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}
