import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/git_identity.dart';
import '../../../data/models/remote_info.dart';
import '../../../data/repositories/panel_tabs_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../workspace/workspace_screen.dart' show repoIdForRoute;

/// Repository → Settings…
///
/// Spec page 06: "四個分頁：General / Remotes / Identity / Performance。原本
/// 佔用主視窗中央，現已移除改為 dialog."
///
/// Per-repository, and therefore separate from the application-level
/// Preferences dialog (spec page 11), which this used to be conflated with:
/// `filePreferences` and `repositorySettings` both opened the same
/// repo-scoped dialog, so Ctrl/Cmd+, landed on Git identity rather than on
/// application settings.
///
/// Routed as `/repo/:repoId/dialogs/repository-settings`.
class RepositorySettingsDialogContent extends ConsumerStatefulWidget {
  const RepositorySettingsDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<RepositorySettingsDialogContent> createState() =>
      _RepositorySettingsDialogContentState();
}

enum _SettingsTab { general, remotes, identity, performance }

class _RepositorySettingsDialogContentState
    extends ConsumerState<RepositorySettingsDialogContent> {
  _SettingsTab _tab = _SettingsTab.general;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _editedSinceLoad = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final RepoSessionController notifier = ref.read(
        repoSessionProvider(widget.identity).notifier,
      );
      notifier.refreshLocalIdentity();
      notifier.refreshEffectiveIdentity();
      notifier.refreshHasCommitGraph();
      notifier.refreshRemotes();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _syncControllersFrom(LocalIdentity identity) {
    if (_editedSinceLoad) return;
    _nameController.text = identity.name;
    _emailController.text = identity.email;
  }

  // Tab names stay English -- `DIALOGS`' own note names them in English
  // even inside its Chinese sentence: 「四個分頁：General / Remotes /
  // Identity / Performance。」
  static String _tabLabel(_SettingsTab tab) => switch (tab) {
    _SettingsTab.general => 'General',
    _SettingsTab.remotes => 'Remotes',
    _SettingsTab.identity => 'Identity',
    _SettingsTab.performance => 'Performance',
  };

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    _syncControllersFrom(session.localIdentity);

    return GbmDialogShell(
      title: 'Repository Settings',
      width: 600,
      actions: <Widget>[
        GbmButton(
          label: 'Close',
          kind: GbmButtonKind.primary,
          onPressed: () => context.pop(),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _TabStrip(
            tabs: _SettingsTab.values,
            current: _tab,
            labelOf: _tabLabel,
            onSelected: (_SettingsTab tab) => setState(() => _tab = tab),
          ),
          const SizedBox(height: GbmSpacing.space3),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220, maxHeight: 380),
            child: SingleChildScrollView(
              child: switch (_tab) {
                _SettingsTab.general => _GeneralTab(identity: widget.identity),
                _SettingsTab.remotes => _RemotesTab(
                  remotes: session.remotes,
                  identity: widget.identity,
                ),
                _SettingsTab.identity => _IdentityTab(
                  session: session,
                  nameController: _nameController,
                  emailController: _emailController,
                  onEdited: () => setState(() => _editedSinceLoad = true),
                  onApply: () {
                    ref
                        .read(repoSessionProvider(widget.identity).notifier)
                        .setLocalIdentity(
                          _nameController.text.trim(),
                          _emailController.text.trim(),
                        );
                    setState(() => _editedSinceLoad = false);
                  },
                  onClear: () {
                    ref
                        .read(repoSessionProvider(widget.identity).notifier)
                        .clearLocalIdentity();
                    setState(() => _editedSinceLoad = false);
                  },
                ),
                _SettingsTab.performance => _PerformanceTab(
                  session: session,
                  onOptimize: () => ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .writeCommitGraph(),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal tab strip. Local to this dialog rather than promoted to
/// `widgets/`: the workspace's own `TabRow` is a different component with
/// close buttons and badges, and nothing else in the app needs a plain strip
/// yet -- promoting it on a sample of one would be guessing at the shared
/// shape.
class _TabStrip<T> extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.current,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> tabs;
  final T current;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          for (final T tab in tabs)
            InkWell(
              onTap: () => onSelected(tab),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: GbmSpacing.space3,
                  vertical: GbmSpacing.space2,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tab == current
                          ? colors.accent
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  labelOf(tab),
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    fontWeight: tab == current
                        ? GbmTypography.weightSemibold
                        : GbmTypography.weightRegular,
                    color: tab == current
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GbmSpacing.space2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: GbmTypography.textXs,
          fontWeight: GbmTypography.weightSemibold,
          color: context.gbmColors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _GeneralTab extends StatelessWidget {
  const _GeneralTab({required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionLabel('位置'),
        SelectableText(
          identity.workDir,
          style: TextStyle(
            fontFamily: GbmTypography.fontMono,
            fontSize: GbmTypography.textSm,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionLabel('維護'),
        Wrap(
          spacing: GbmSpacing.space2,
          runSpacing: GbmSpacing.space2,
          children: <Widget>[
            _PanelLinkButton(
              identity: identity,
              label: 'Manage worktrees…',
              kind: GbmPanelKind.manageWorktrees,
            ),
            _PanelLinkButton(
              identity: identity,
              label: 'Manage submodules…',
              kind: GbmPanelKind.manageSubmodules,
            ),
            _PanelLinkButton(
              identity: identity,
              label: 'Manage LFS…',
              kind: GbmPanelKind.manageLfs,
            ),
            GbmButton(
              label: 'Clean untracked files…',
              onPressed: () => context.push(
                RoutePaths.cleanUntrackedDialogFor(repoIdForRoute(identity)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RemotesTab extends StatelessWidget {
  const _RemotesTab({required this.remotes, required this.identity});

  final List<RemoteInfo> remotes;
  final RepoIdentity identity;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionLabel('遠端'),
        if (remotes.isEmpty)
          Text(
            '這個 repository 沒有 remote。',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textTertiary,
            ),
          )
        else
          for (final RemoteInfo remote in remotes)
            Padding(
              padding: const EdgeInsets.only(bottom: GbmSpacing.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    remote.name,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      fontWeight: GbmTypography.weightSemibold,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    remote.fetchUrl,
                    style: TextStyle(
                      fontFamily: GbmTypography.fontMono,
                      fontSize: GbmTypography.textXs,
                      color: colors.textSecondary,
                    ),
                  ),
                  // Only shown when it actually differs -- repeating an
                  // identical URL twice reads as a second remote.
                  if (remote.pushUrl.isNotEmpty &&
                      remote.pushUrl != remote.fetchUrl)
                    Text(
                      '推送：${remote.pushUrl}',
                      style: TextStyle(
                        fontFamily: GbmTypography.fontMono,
                        fontSize: GbmTypography.textXs,
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
        const SizedBox(height: GbmSpacing.space2),
        Row(
          children: <Widget>[
            _PanelLinkButton(
              identity: identity,
              label: 'Manage remotes…',
              kind: GbmPanelKind.manageRemotes,
            ),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(
              label: 'Prune remote branches…',
              onPressed: () => context.push(
                RoutePaths.pruneRemoteBranchesDialogFor(
                  repoIdForRoute(identity),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IdentityTab extends StatelessWidget {
  const _IdentityTab({
    required this.session,
    required this.nameController,
    required this.emailController,
    required this.onEdited,
    required this.onApply,
    required this.onClear,
  });

  final RepoSessionState session;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final VoidCallback onEdited;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionLabel('GIT 身份'),
        Text(
          '此處新 commit 會使用：${session.effectiveIdentity.name} '
          '<${session.effectiveIdentity.email}>',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        TextField(
          controller: nameController,
          onChanged: (_) => onEdited(),
          decoration: const InputDecoration(
            labelText: '名稱（僅限此 repository）',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        TextField(
          controller: emailController,
          onChanged: (_) => onEdited(),
          decoration: const InputDecoration(
            labelText: 'Email（僅限此 repository）',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        Row(
          children: <Widget>[
            GbmButton(
              label: 'Apply Override',
              kind: GbmButtonKind.primary,
              onPressed:
                  nameController.text.trim().isEmpty ||
                      emailController.text.trim().isEmpty
                  ? null
                  : onApply,
            ),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(
              label: 'Clear Override',
              onPressed: session.localIdentity.overridden ? onClear : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _PerformanceTab extends StatelessWidget {
  const _PerformanceTab({required this.session, required this.onOptimize});

  final RepoSessionState session;
  final VoidCallback onOptimize;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 保留 "COMMIT-GRAPH" 不譯：這是 git 內部物件的專有名稱，不是一般
        // 英文詞組，跟本頁其餘的自組區段標籤不同。
        const _SectionLabel('COMMIT-GRAPH'),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                session.hasCommitGraph
                    ? '這個 repository 已經有 commit-graph。'
                    : 'commit-graph 可以加快大型 repository 讀取歷史的速度。',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(label: 'Optimize Now', onPressed: onOptimize),
          ],
        ),
        if (session.lastCommitGraphWriteSucceeded case final succeeded?)
          Padding(
            padding: const EdgeInsets.only(top: GbmSpacing.space1),
            child: Text(
              succeeded ? 'commit-graph 已寫入。' : '寫入 commit-graph 失敗。',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: succeeded ? colors.success : colors.danger,
              ),
            ),
          ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionLabel('歷史'),
        Text(
          '已載入 ${session.graph.rows.length} 個 commit，共 '
          '${session.graph.laneCount} 個 lane。',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Opens one of spec page 14's management panels as a **tab**, from inside
/// this dialog.
///
/// Two things it does that a plain `context.push` would not, and both
/// matter: it registers the tab with [panelTabsProvider] (a tab that is not
/// in that list renders "This panel is no longer open"), and it pops the
/// dialog *before* navigating — a tab replaces the shell's child, so leaving
/// the modal up would hide the thing the user just asked for.
///
/// A [Consumer] because `_GeneralTab` is a [StatelessWidget] with no `ref`.
class _PanelLinkButton extends StatelessWidget {
  const _PanelLinkButton({
    required this.identity,
    required this.label,
    required this.kind,
  });

  final RepoIdentity identity;
  final String label;
  final GbmPanelKind kind;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => GbmButton(
        label: label,
        onPressed: () {
          final String tabId = ref
              .read(panelTabsProvider(identity).notifier)
              .open(kind);
          context.pop();
          context.go(RoutePaths.panelFor(repoIdForRoute(identity), tabId));
        },
      ),
    );
  }
}
