import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../data/models/worktree_info.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../data/services/file_save_picker.dart';
import '../../../routing/app_router.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_field_kinds.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';
import '../../../widgets/gbm_ref_picker.dart';
import '../branch_name_validation.dart';

/// Which git operation `Add worktree` runs: check an existing ref out into
/// the new worktree, or create a fresh branch there.
enum WorktreeSource { checkoutExisting, createNew }

/// The Worktrees panel's `Add worktree…` (D1). Previously an inline form
/// expanded above the list, with `createBranch: true` hardcoded -- so it
/// could only ever create a new branch, even though its own hint text said
/// "leave empty to check out an existing one". This is the dialog that
/// replaces it.
///
/// **The branch field is [GbmRefPicker], the same control New branch and
/// Checkout use** -- D1's own row says so ("與 Checkout 的 focus 用同一顆").
/// It plays two roles depending on [WorktreeSource]: the branch to check
/// out, or the new branch's start point. A branch already checked out in
/// another worktree is disabled and annotated with which one -- only in
/// [WorktreeSource.checkoutExisting], where git would otherwise refuse it;
/// as a start point for a *new* branch that branch is a completely
/// ordinary choice.
///
/// **The default path is the primary worktree's own directory, not
/// `identity.workDir`** -- opening gbm on a linked worktree makes the
/// latter wrong, which is why `isMain` (this session's worktree) and
/// `isPrimary` (the repository's main one) are two different flags on
/// [WorktreeInfo]. `&lt;dirname of the primary worktree&gt;/worktrees/&lt;branch
/// name, `/` replaced with `-`&gt;`, recomputed as the branch selection
/// changes and left alone the moment the user edits the field by hand --
/// the same "computed until touched" rule Clone dialogs elsewhere use for
/// a URL-derived folder name.
///
/// A path that already exists and is not empty is exactly what git itself
/// refuses (`fatal: … already exists`), so the warning names that before
/// the click, not after.
///
/// **"建立後切換到這個 worktree" defaults off**: switching replaces the
/// whole window's repository, a much bigger action than creating a
/// worktree, so an inert-by-default checkbox is the read [待裁定 2] in the
/// plan settled on.
///
/// Routed as `/repo/:repoId/dialogs/add-worktree` -- not one of the spec's
/// 22 dialogs, since the Worktrees panel itself postdates the spec's own
/// page 06 dialog list ([STRUCT-panels-are-tabs]).
class AddWorktreeDialogContent extends ConsumerStatefulWidget {
  const AddWorktreeDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<AddWorktreeDialogContent> createState() =>
      _AddWorktreeDialogContentState();
}

class _AddWorktreeDialogContentState
    extends ConsumerState<AddWorktreeDialogContent> {
  WorktreeSource _source = WorktreeSource.checkoutExisting;

  /// The picker's current selection. Deliberately one field for both modes
  /// -- D1's mockup draws one picker, not two -- so switching [_source]
  /// keeps whatever was picked unless the new mode would make it invalid
  /// (see [_setSource]).
  GbmRefPickerEntry? _picked;

  /// Whether [_picked] has been given its one-time default yet. Mirrors
  /// New branch dialog's `_startRefResolved`, but scoped to
  /// [WorktreeSource.createNew]: [WorktreeSource.checkoutExisting] has no
  /// sensible default (the current branch is, by construction, already
  /// checked out in the primary worktree and would default straight into a
  /// disabled row), so only entering create-new mode ever resolves it.
  bool _startResolved = false;

  final TextEditingController _newBranchNameController =
      TextEditingController();
  final TextEditingController _pathController = TextEditingController();

  /// Once true, [build] stops overwriting the path field with the computed
  /// default -- the same escape hatch a pasted-URL-derived folder name
  /// needs elsewhere.
  bool _pathManuallyEdited = false;

  bool _switchAfter = false;

  @override
  void dispose() {
    _newBranchNameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  RepoSessionState get _session =>
      ref.read(repoSessionProvider(widget.identity));

  /// D5: the same picker context 05-K's "Save this revision as…" and the
  /// patches/changed-files panels already use, wired into a second field
  /// that used to be a plain path text box with nothing beside it.
  Future<void> _browsePath() async {
    final String? dir = await ref.read(fileSavePickerProvider).pickDirectory();
    if (dir == null || !mounted) return;
    setState(() {
      _pathController.text = dir;
      _pathManuallyEdited = true;
    });
  }

  void _setSource(WorktreeSource? source) {
    if (source == null || source == _source) return;
    final RepoSessionState session = _session;
    setState(() {
      _source = source;
      // Whatever was picked under the old mode is not necessarily valid
      // under the new one -- checkout-existing disables an occupied local
      // branch, create-new does not. A selected-but-disabled row is a state
      // git could not act on, so it is cleared rather than carried over.
      if (_picked != null &&
          !_entries(session).any(
            (GbmRefPickerEntry e) => e.name == _picked!.name && e.enabled,
          )) {
        _picked = null;
      }
    });
  }

  /// `origin/feature/x` -> `feature/x`. Duplicated from
  /// `checkout_dialog.dart`'s own `_localNameFor` rather than shared: both
  /// are two-line pure functions over the *short* form `GbmRefPickerEntry`
  /// carries, which is a different shape from `remoteBranchParts()`'s full
  /// `refs/remotes/...` input, so sharing would mean reshaping one side's
  /// data just to call a helper.
  static String _localNameFor(String remoteShortName) {
    final int slash = remoteShortName.indexOf('/');
    return slash == -1 ? remoteShortName : remoteShortName.substring(slash + 1);
  }

  /// Every local branch already checked out somewhere, mapped to that
  /// worktree's directory name -- the mockup's 「已在 gbm」. A detached
  /// worktree contributes nothing: it holds no branch for another worktree
  /// to collide with.
  Map<String, String> _occupiedBranches(List<WorktreeInfo> worktrees) => {
    for (final WorktreeInfo w in worktrees)
      if (!w.isDetached && w.branch.isNotEmpty)
        w.branch: w.path.split('/').last,
  };

  List<GbmRefPickerEntry> _entries(RepoSessionState session) {
    final Map<String, String> occupied = _occupiedBranches(session.worktrees);
    // Only checkout-existing cares: as a start point for a brand new
    // branch, an occupied branch is an entirely ordinary choice.
    final bool gateOnOccupancy = _source == WorktreeSource.checkoutExisting;
    final String head = session.refs.head.branchName;

    return <GbmRefPickerEntry>[
      for (final RefInfo b in session.refs.localBranches)
        GbmRefPickerEntry(
          name: b.shortName,
          kind: GbmRefKind.localBranch,
          enabled: !gateOnOccupancy || !occupied.containsKey(b.shortName),
          // The annotation itself, not just the picker's `selected` flag,
          // has to come from this list -- GbmRefPicker renders an entry's
          // own `annotation`, never anything held on the caller's side, so
          // marking the default choice anywhere else draws no label at all.
          annotation: gateOnOccupancy && occupied.containsKey(b.shortName)
              ? '已在 ${occupied[b.shortName]}'
              : (!gateOnOccupancy && b.shortName == head ? '目前分支' : ''),
        ),
      for (final RefInfo b in session.refs.remoteBranches)
        GbmRefPickerEntry(name: b.shortName, kind: GbmRefKind.remoteBranch),
      for (final RefInfo t in session.refs.tags)
        GbmRefPickerEntry(name: t.shortName, kind: GbmRefKind.tag),
    ];
  }

  static String? _primaryWorktreePath(List<WorktreeInfo> worktrees) => worktrees
      .where((WorktreeInfo w) => w.isPrimary)
      .map((WorktreeInfo w) => w.path)
      .firstOrNull;

  /// No `package:path` dependency in this app (see
  /// `working_copy_view.dart`'s `_absolutePathOf`) -- git always reports
  /// `/`-separated paths, so a manual trim is enough.
  static String _dirname(String path) {
    final String trimmed = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final int slash = trimmed.lastIndexOf('/');
    return slash <= 0 ? trimmed : trimmed.substring(0, slash);
  }

  /// The repository's own directory name, so two checkouts sitting side by
  /// side under one parent do not propose the same worktree directory.
  /// Empty only for a repository at the filesystem root, where the segment
  /// is dropped rather than rendered as an empty one.
  static String _basename(String path) {
    final String trimmed = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final int slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }

  /// D1's rule 4: `&lt;primary worktree's own dirname&gt;/worktrees/&lt;the
  /// repository's own directory name&gt;/&lt;branch name, `/` -&gt; `-`&gt;`.
  /// Null when there is nothing to base a default on yet (no primary
  /// worktree known, or no branch picked/typed) -- the field then simply
  /// starts empty rather than guessing.
  ///
  /// The repository segment is not decoration. Without it `~/code/gbm` and
  /// `~/code/other` both default to `~/code/worktrees/main`, so whichever
  /// repository the user opens second meets 「已存在且不是空的」 before it
  /// has been touched -- the reported defect.
  String? _computeDefaultPath(List<WorktreeInfo> worktrees, String branchName) {
    if (branchName.isEmpty) return null;
    final String? primary = _primaryWorktreePath(worktrees);
    if (primary == null) return null;
    final String repo = _basename(primary);
    final String leaf = branchName.replaceAll('/', '-');
    final String root = '${_dirname(primary)}/worktrees';
    return repo.isEmpty ? '$root/$leaf' : '$root/$repo/$leaf';
  }

  bool _pathExistsAndNonEmpty(String path) {
    if (path.isEmpty) return false;
    final Directory dir = Directory(path);
    return dir.existsSync() && dir.listSync().isNotEmpty;
  }

  void _submit(RepoSessionState session) {
    final String path = _pathController.text.trim();
    if (path.isEmpty) return;
    final RepoSessionController controller = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );

    switch (_source) {
      case WorktreeSource.checkoutExisting:
        final GbmRefPickerEntry? entry = _picked;
        if (entry == null) return;
        if (entry.kind == GbmRefKind.remoteBranch) {
          // Explicit, not relied-on DWIM: `git worktree add <path>
          // <remote-branch-short-name>` auto-creates a tracking local
          // branch on its own (measured), but naming both the start point
          // and the new branch is what Checkout's own dialog already does
          // for the identical case, and one rule beats two that happen to
          // agree today.
          controller.addWorktree(
            path,
            branch: entry.name,
            createBranch: true,
            newBranchName: _localNameFor(entry.name),
          );
        } else {
          // A tag or a bare commit here detaches on its own (measured: `git
          // worktree add <path> <tag>` reports "Preparing worktree
          // (detached HEAD …)" with no `--detach` given), so nothing extra
          // is passed for those kinds either.
          controller.addWorktree(path, branch: entry.name);
        }
      case WorktreeSource.createNew:
        final String newName = _newBranchNameController.text.trim();
        if (newName.isEmpty) return;
        controller.addWorktree(
          path,
          branch: _picked?.name ?? '',
          createBranch: true,
          newBranchName: newName,
        );
    }

    if (_switchAfter) {
      context.go(RoutePaths.workspaceFor(repoIdFor(path)));
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );

    if (_source == WorktreeSource.createNew && !_startResolved) {
      _startResolved = true;
      // Only when nothing is picked yet -- entering create-new mode after
      // already having picked a branch in checkout-existing mode (D1's
      // picker is one field, not two) must keep that pick, not silently
      // replace it with the default the very first entry would have gotten.
      if (_picked == null) {
        final String head = session.refs.head.branchName;
        _picked = GbmRefPickerEntry(
          name: head.isNotEmpty ? head : 'HEAD',
          kind: GbmRefKind.localBranch,
          annotation: head.isNotEmpty ? '目前分支' : '',
        );
      }
    }

    final String effectiveBranchName =
        _source == WorktreeSource.checkoutExisting
        ? (_picked?.name ?? '')
        : _newBranchNameController.text.trim();
    if (!_pathManuallyEdited) {
      final String? computed = _computeDefaultPath(
        session.worktrees,
        effectiveBranchName,
      );
      if (computed != null && computed != _pathController.text) {
        _pathController.text = computed;
      }
    }

    final String path = _pathController.text.trim();
    final bool pathTaken = _pathExistsAndNonEmpty(path);

    final List<String> existingLocalNames = session.refs.localBranches
        .map((RefInfo b) => b.shortName)
        .toList(growable: false);
    final String? nameError = _source == WorktreeSource.createNew
        ? branchNameError(
            _newBranchNameController.text,
            existingNames: existingLocalNames,
          )
        : null;

    final bool canSubmit =
        path.isNotEmpty &&
        !pathTaken &&
        switch (_source) {
          WorktreeSource.checkoutExisting => _picked != null,
          WorktreeSource.createNew =>
            _newBranchNameController.text.trim().isNotEmpty &&
                nameError == null,
        };

    return GbmDialogShell(
      title: 'Add Worktree',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Add worktree',
          kind: GbmButtonKind.primary,
          onPressed: canSubmit ? () => _submit(session) : null,
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // spec's G2: the radios were the only field with no group
            // label. Same P6 treatment as '分支' below (spec's G3) --
            // 使用者裁定：加「來源」標籤.
            Text(
              '來源',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            RadioGroup<WorktreeSource>(
              groupValue: _source,
              onChanged: _setSource,
              child: const Column(
                children: <Widget>[
                  RadioListTile<WorktreeSource>(
                    value: WorktreeSource.checkoutExisting,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('checkout 既有分支'),
                  ),
                  RadioListTile<WorktreeSource>(
                    value: WorktreeSource.createNew,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('建立新分支'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            // P6 field-label treatment (spec's G3): 11px / textSecondary /
            // sentence case -- not the pane-header style (semibold,
            // letter-spaced, textTertiary) this used to share with
            // Preferences' section headings.
            Text(
              '分支',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            GbmRefPicker(
              entries: _entries(session),
              selected: _picked?.name,
              maxListHeight: 200,
              onSelected: (GbmRefPickerEntry entry) =>
                  setState(() => _picked = entry),
            ),
            const SizedBox(height: GbmSpacing.space3),
            // P6 field-label treatment (spec's G3), same as '分支'/'來源'
            // above -- see gbm_input_decoration.dart's doc comment for why
            // this is an external Text and not InputDecoration.labelText.
            Text(
              '新分支名',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            SizedBox(
              height: GbmSpacing.inputHeight,
              child: TextField(
                key: const Key('add-worktree-new-branch-name-field'),
                controller: _newBranchNameController,
                // Dimmed, not hidden, while unused -- 比照 Create tag 的
                // 「訊息」欄, and generally [FLU-menu-enabled-is-visual-only]'s
                // rule against a control that silently does nothing.
                enabled: _source == WorktreeSource.createNew,
                onChanged: (_) => setState(() {}),
                decoration: gbmInputDecoration(
                  colors: colors,
                  hintText: 'feature/x',
                  errorText: nameError,
                ),
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
            Text(
              '位置',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: GbmSpacing.inputHeight,
                    child: TextField(
                      key: const Key('add-worktree-path-field'),
                      controller: _pathController,
                      onChanged: (_) =>
                          setState(() => _pathManuallyEdited = true),
                      decoration: gbmInputDecoration(colors: colors),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                GbmButton(
                  label: '瀏覽…',
                  kind: GbmButtonKind.secondary,
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: _browsePath,
                ),
              ],
            ),
            const SizedBox(height: GbmSpacing.space2),
            CheckboxListTile(
              value: _switchAfter,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '建立後切換到這個 worktree',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (bool? value) =>
                  setState(() => _switchAfter = value ?? false),
            ),
            if (pathTaken) ...<Widget>[
              const SizedBox(height: GbmSpacing.space2),
              // G8b: dialog-internal warnings use GbmDialogWarnField, not
              // GbmWarningBanner (screen-level only).
              GbmDialogWarnField(message: '$path 已存在且不是空的，git 會拒絕。'),
            ],
          ],
        ),
      ),
    );
  }
}
