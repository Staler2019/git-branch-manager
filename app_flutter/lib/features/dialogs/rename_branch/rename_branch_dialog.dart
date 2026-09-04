import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';
import '../branch_name_validation.dart';

/// Which of spec page 13's two "遠端連帶處理" options is selected.
enum RenameRemoteMode {
  /// Push the new name (with `-u`), then delete the old branch on the remote.
  alsoRenameRemote,

  /// Leave the remote alone; the renamed branch ends up with no upstream.
  localOnly,
}

/// Branch → Rename branch… (F2) and context menu 05-B's "Rename branch".
///
/// Spec page 13 section A ("Rename branch — 單一分支"), the design that was
/// added on 260820 and that issue #45 was waiting for. Four parts, in order:
/// the current name restated read-only, the new name with live validation,
/// the remote handling choice, and a warning that spells out what renaming
/// on the remote actually costs.
///
/// The dialog does not wait for the operation: spec page 10's rule is that
/// progress and failures belong to the background-task row and the error
/// window, "不留在 dialog 裡轉圈", so the confirm button dispatches and pops
/// immediately, exactly as every other dialog here does.
///
/// Renaming the *current* branch is allowed and needs no checkout first --
/// git moves HEAD along with the branch.
///
/// Routed as `/repo/:repoId/dialogs/rename-branch`.
class RenameBranchDialogContent extends ConsumerStatefulWidget {
  const RenameBranchDialogContent({
    super.key,
    required this.identity,
    this.branchName,
  });

  final RepoIdentity identity;

  /// The branch to rename. Null (Branch → Rename branch…, or F2) means the
  /// current branch -- the context menu is the entry point that names one.
  final String? branchName;

  @override
  ConsumerState<RenameBranchDialogContent> createState() =>
      _RenameBranchDialogContentState();
}

class _RenameBranchDialogContentState
    extends ConsumerState<RenameBranchDialogContent> {
  final TextEditingController _nameController = TextEditingController();
  RenameRemoteMode _remoteMode = RenameRemoteMode.alsoRenameRemote;

  /// Whether the name field has been seeded with the branch's current name.
  /// Done on first build rather than in initState() because the branch is
  /// only known once the session snapshot is read.
  bool _seeded = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );

    // Spec page 13: "分支正在被 rebase / merge 佔用 -> 整個 dialog 不開啟,
    // 改出提示「先完成或中止進行中的作業」". Every entry point is already
    // gated on this (isActionEnabled / BranchTreeItem.conflictActive), so
    // reaching here mid-conflict means the route was entered directly --
    // refuse rather than offer a rename that would move HEAD. Same shape as
    // the discard-changes dialog's malformed-request state: no destructive
    // button at all, only a way out.
    if (session.conflictActive) {
      return GbmDialogShell(
        title: 'Rename Branch',
        actionId: GbmActionId.branchRenameCurrentBranch,
        actions: <Widget>[
          GbmButton(label: 'Close', onPressed: () => context.pop()),
        ],
        child: Text(
          // RENAMEVALID row 5，逐字引用。
          '先完成或中止進行中的作業',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textPrimary,
          ),
        ),
      );
    }

    final String targetName = widget.branchName ?? session.refs.head.branchName;

    RefInfo? target;
    for (final RefInfo b in session.refs.localBranches) {
      if (b.shortName == targetName) target = b;
    }

    if (target == null) {
      return GbmDialogShell(
        title: 'Rename Branch',
        actionId: GbmActionId.branchRenameCurrentBranch,
        actions: <Widget>[
          GbmButton(label: 'Close', onPressed: () => context.pop()),
        ],
        child: Text(
          targetName.isEmpty
              ? 'HEAD 目前是 detached，沒有分支可以更名。'
              : '沒有名為「$targetName」的本地分支。',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textPrimary,
          ),
        ),
      );
    }

    final RefInfo branch = target;
    if (!_seeded) {
      _nameController.text = branch.shortName;
      _seeded = true;
    }

    // The branch's own name is not a collision -- it is the "未改動" case,
    // which disables the button without any red text.
    final List<String> existingNames = session.refs.localBranches
        .map((RefInfo b) => b.shortName)
        .where((String name) => name != branch.shortName)
        .toList(growable: false);

    final String typed = _nameController.text.trim();
    final String? error = branchNameError(typed, existingNames: existingNames);
    final bool changed = typed.isNotEmpty && typed != branch.shortName;
    final bool canRename = changed && error == null;

    // RefInfo.upstream is git's `%(upstream)` -- the tracked ref's *full*
    // name (refs/remotes/origin/main), not `%(upstream:short)`. Splitting it
    // on the first slash would yield "refs"; remoteBranchParts() is the
    // helper that already knows that.
    // Keyed on `upstream` alone, deliberately *not* on `hasTrackingInfo`:
    // the latter mirrors git's `%(upstream:track)`, which is empty for a
    // branch exactly in sync with its upstream (0 ahead, 0 behind) even
    // though `%(upstream)` is populated -- see RefStore.cpp's parseTrack().
    // Conjoining the two hid this whole section for a freshly-pushed
    // branch, quietly turning every such rename into a local-only one.
    final bool hasUpstream = branch.upstream.isNotEmpty;
    final (String remote, String remoteBranch) = hasUpstream
        ? remoteBranchParts(branch.upstream)
        : ('', '');
    final bool renameRemote =
        hasUpstream && _remoteMode == RenameRemoteMode.alsoRenameRemote;

    return GbmDialogShell(
      title: 'Rename Branch',
      actionId: GbmActionId.branchRenameCurrentBranch,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Rename',
          kind: GbmButtonKind.primary,
          onPressed: canRename
              ? () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .renameBranch(
                        from: branch.shortName,
                        to: typed,
                        renameRemote: renameRemote,
                        remoteName: renameRemote ? remote : '',
                      );
                  context.pop();
                }
              : null,
        ),
      ],
      // GbmDialogShell caps its body's height but does not scroll it, so a
      // dialog whose content can grow (the remote section and its warning
      // only appear for a branch with an upstream) scrolls its own body --
      // the same thing preferences/repository-settings/discard-changes do.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Label(text: '目前名稱'),
            const SizedBox(height: GbmSpacing.space1),
            Row(
              children: <Widget>[
                Icon(
                  Icons.call_split,
                  size: GbmTypography.textSm,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: GbmSpacing.space1),
                Expanded(
                  child: Text(
                    branch.shortName,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      fontFamily: GbmTypography.fontMono,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GbmSpacing.space3),
            _Label(text: '新名稱'),
            const SizedBox(height: GbmSpacing.space1),
            SizedBox(
              height: GbmSpacing.inputHeight,
              child: TextField(
                controller: _nameController,
                autofocus: true,
                decoration: gbmInputDecoration(
                  colors: colors,
                  hintText: '新的分支名稱',
                  errorText: error,
                ),
                // Spec page 13: validation is live, "即時，不等到按 Rename".
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (!canRename) return;
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .renameBranch(
                        from: branch.shortName,
                        to: typed,
                        renameRemote: renameRemote,
                        remoteName: renameRemote ? remote : '',
                      );
                  context.pop();
                },
              ),
            ),
            if (canRename) ...<Widget>[
              const SizedBox(height: GbmSpacing.space1),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.check,
                    size: GbmTypography.textSm,
                    color: colors.success,
                  ),
                  const SizedBox(width: GbmSpacing.space1),
                  Text(
                    '可以使用 — 沒有同名的分支。',
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: colors.success,
                    ),
                  ),
                ],
              ),
            ],
            if (hasUpstream) ...<Widget>[
              const SizedBox(height: GbmSpacing.space3),
              // P13-A mock 第 3 項標籤，逐字引用。
              _Label(text: '遠端連帶處理'),
              RadioGroup<RenameRemoteMode>(
                groupValue: _remoteMode,
                onChanged: (RenameRemoteMode? mode) =>
                    setState(() => _remoteMode = mode ?? _remoteMode),
                child: Column(
                  children: <Widget>[
                    // P13-A mock 的兩個 radio 選項，逐字引用（説明欄的
                    // $remote/$remoteBranch 沿用 mock 的
                    // 「origin/feature/lane-allocator」格式）。
                    _RemoteOption(
                      mode: RenameRemoteMode.alsoRenameRemote,
                      label: '一併更名遠端分支',
                      description: 'push 新名稱，再刪除 $remote/$remoteBranch',
                    ),
                    _RemoteOption(
                      mode: RenameRemoteMode.localOnly,
                      label: '只改本地，保留遠端舊分支',
                      description: '新分支的 upstream 會清空',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GbmSpacing.space2),
              _Warning(
                // renameRemote 時引用 P13-A mock 第 4 項警語；未勾選時是
                // RENAMEVALID row 4 的 hint。兩者都附上 ahead 數字，比照
                // delete-branch 對話框「永遠顯示實際數字」的既有作法。
                text: renameRemote
                    ? '遠端更名 = delete + push，其他人的 tracking branch 會變成 '
                          'gone。${_aheadPhrase(branch)}'
                    : '新分支不會有 upstream，之後需重新 push -u。'
                          '${_aheadPhrase(branch)}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ahead is what the refs snapshot actually carries, so it is reported as
  /// exactly that -- spec page 02 item 11's "永遠顯示實際數字" applies here
  /// the same way it does in the delete-branch dialog.
  static String _aheadPhrase(RefInfo branch) => branch.ahead > 0
      ? '此分支目前有 ${branch.ahead} 個未 push 的 commit。'
      : '此分支目前沒有未 push 的 commit。';
}

/// P6 field-label treatment (worktree-dialogs-spec.html's G3): 11px /
/// textSecondary / sentence case. Missed by G3's original sweep across the
/// other three dialogs -- this class has no `letterSpacing`, so it did not
/// match the grep that found those -- but it is the same shape (a label
/// sitting directly above one control), so it gets the same fix.
class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: GbmTypography.textXs,
        color: context.gbmColors.textSecondary,
      ),
    );
  }
}

class _RemoteOption extends StatelessWidget {
  const _RemoteOption({
    required this.mode,
    required this.label,
    required this.description,
  });

  final RenameRemoteMode mode;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return RadioListTile<RenameRemoteMode>(
      value: mode,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: TextStyle(
          fontSize: GbmTypography.textSm,
          color: colors.textPrimary,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          fontSize: GbmTypography.textXs,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.warning_amber_outlined,
          size: GbmTypography.textSm,
          color: colors.warning,
        ),
        const SizedBox(width: GbmSpacing.space1),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.warning,
            ),
          ),
        ),
      ],
    );
  }
}
