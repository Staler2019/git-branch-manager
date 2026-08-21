import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/panel_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
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
/// Spec page 14's `IAMAP` assigns twelve panels to this carrier. They are
/// being ported one at a time (each its own commit), so [GbmPanelKind] has
/// twelve values while this switch only builds the ones that have landed;
/// the rest fall through to [_NotYetPortedPanel], which says so plainly
/// rather than rendering blank. Progress is tracked on issue #76.
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
      _ => _NotYetPortedPanel(kind: spec.kind),
    };
  }
}

/// Shown for a [GbmPanelKind] whose dialog has not been ported to a tab yet.
/// Naming the panel and pointing at the tracking issue beats an empty pane,
/// which reads as a rendering bug rather than as unfinished work.
class _NotYetPortedPanel extends StatelessWidget {
  const _NotYetPortedPanel({required this.kind});

  final GbmPanelKind kind;

  @override
  Widget build(BuildContext context) {
    return _PanelMessage(
      message: '${kind.label} has not been ported to a tab yet (see #76)',
    );
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
