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
import '../../../widgets/gbm_ref_picker.dart';
import '../branch_name_validation.dart';

/// Branch → New branch… (Ctrl/Cmd+Shift+B), and the "New branch from here…"
/// entries in context menus 05-B and 05-E.
///
/// **The start point is one searchable list, not a three-way dropdown.**
/// Spec page 06's row words it 「起點（下拉：目前分支 / 指定 commit / tag）」,
/// and P17's `REVISIONS`-era row for the same dialog words it as a single
/// 從哪裡分出 field over 「可搜尋的混合清單：branch / tag / commit，以圖示
/// 區分」 — the wording Checkout's own row uses. P17 is the later page, and
/// [SPEC-21-pages-and-revisions] says a later page revises an earlier one,
/// so this deliberately overrules P06's dropdown.
///
/// That is also what fixes the defect the shape was hiding: the old free-text
/// half was a bare `TextField` with **no controller and no `initialValue`**,
/// so an [initialStartPoint] arriving from a commit row lived in state and
/// was drawn nowhere — the dialog showed two empty boxes and created the
/// branch at a start point the user could not see.
///
/// The duplicate-name check still runs on every keystroke and disables the
/// primary button (P06: 「名稱重複即時擋下」) rather than letting the create
/// round-trip to git and come back as an error banner.
///
/// **「同時 push 並設為 upstream」** is offered only when the repository has
/// exactly one remote -- the same "none or several, don't guess" rule
/// `branch_bulk_actions.dart`'s `soleRemoteName()` already uses for bulk
/// push. It dispatches a *second* operation, `pushChanges(remoteName:,
/// branches: [name], setUpstream: true)`, never `createBranch`'s own
/// `setUpstream`/`upstream` params -- those run `git branch --track
/// &lt;upstream&gt;`, which needs the remote-tracking ref to already exist, and a
/// first push has no such ref yet. `RepoSessionState.remotes` is not
/// populated at session open, so this dialog asks for it itself in
/// `initState`, the way the manage-remotes panel does.
///
/// Routed as `/repo/:repoId/dialogs/new-branch`.
class NewBranchDialogContent extends ConsumerStatefulWidget {
  const NewBranchDialogContent({
    super.key,
    required this.identity,
    this.initialStartPoint,
  });

  final RepoIdentity identity;

  /// Set when opened from a branch or commit row. A value that names no ref
  /// — an abbreviated oid from a commit row — is added to the list as a
  /// commit entry, because a preselection the list cannot show is the same
  /// as no preselection at all from the user's side.
  final String? initialStartPoint;

  @override
  ConsumerState<NewBranchDialogContent> createState() =>
      _NewBranchDialogContentState();
}

class _NewBranchDialogContentState
    extends ConsumerState<NewBranchDialogContent> {
  final TextEditingController _nameController = TextEditingController();

  /// Null until the first build resolves the default, which needs the
  /// session — `initState` has no `ref.watch`, and reading the current
  /// branch there would freeze it against a snapshot that has not arrived.
  String? _startRef;
  bool _startRefResolved = false;
  bool _checkoutAfter = true;
  bool _pushAfterCreate = false;

  @override
  void initState() {
    super.initState();
    // Not populated at session open (see repo_session_repository.dart's own
    // note next to `remotesToPreviewAfterFetch`), so this asks for it the
    // way the manage-remotes panel does on mount.
    Future.microtask(
      () => ref
          .read(repoSessionProvider(widget.identity).notifier)
          .refreshRemotes(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// The repository's only remote, or null when it has none or several --
  /// `branch_bulk_actions.dart`'s `soleRemoteName()` rule, reused rather
  /// than re-derived.
  String? _soleRemote(RepoSessionState session) =>
      session.remotes.length == 1 ? session.remotes.single.name : null;

  /// Every ref the branch can start at, with the current one marked.
  ///
  /// The current branch is annotated rather than removed — unlike Checkout,
  /// where switching to the branch you are on is a no-op, branching *from*
  /// where you stand is the commonest case there is.
  List<GbmRefPickerEntry> _entries(RepoSessionState session) {
    final String head = session.refs.head.branchName;
    final List<GbmRefPickerEntry> entries = <GbmRefPickerEntry>[
      for (final RefInfo b in session.refs.localBranches)
        GbmRefPickerEntry(
          name: b.shortName,
          kind: GbmRefKind.localBranch,
          annotation: b.shortName == head ? '目前分支' : '',
        ),
      for (final RefInfo b in session.refs.remoteBranches)
        GbmRefPickerEntry(name: b.shortName, kind: GbmRefKind.remoteBranch),
      for (final RefInfo t in session.refs.tags)
        GbmRefPickerEntry(name: t.shortName, kind: GbmRefKind.tag),
    ];

    // A start point handed in from a commit row names no ref, so nothing
    // above carries it. Adding it here is what makes the preselection
    // visible; without it the picker would highlight a row that is not in
    // the list, which draws as no highlight at all.
    final String? initial = widget.initialStartPoint;
    if (initial != null &&
        initial.isNotEmpty &&
        !entries.any((GbmRefPickerEntry e) => e.name == initial)) {
      entries.add(GbmRefPickerEntry(name: initial, kind: GbmRefKind.commit));
    }
    return entries;
  }

  /// The default selection: what the caller asked for, else the branch HEAD
  /// is on, else `HEAD` itself for a detached head — which `git branch` reads
  /// as "here", the same thing an empty start point used to mean.
  String _defaultStartRef(RepoSessionState session) {
    final String? initial = widget.initialStartPoint;
    if (initial != null && initial.isNotEmpty) return initial;
    final String head = session.refs.head.branchName;
    return head.isNotEmpty ? head : 'HEAD';
  }

  void _submit() {
    final String name = _nameController.text.trim();
    final RepoSessionController session = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );
    session.createBranch(
      name: name,
      startPoint: _startRef ?? '',
      checkoutAfter: _checkoutAfter,
    );
    if (_pushAfterCreate) {
      final String? remote = _soleRemote(
        ref.read(repoSessionProvider(widget.identity)),
      );
      if (remote != null) {
        session.pushChanges(
          remoteName: remote,
          branches: <String>[name],
          setUpstream: true,
        );
      }
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final String? soleRemote = _soleRemote(session);

    // Resolved once, not per build: re-deriving it every frame would undo
    // the user's own pick the next time anything republishes state.
    if (!_startRefResolved) {
      _startRefResolved = true;
      _startRef = _defaultStartRef(session);
    }

    final List<GbmRefPickerEntry> entries = _entries(session);
    final List<String> existingNames = session.refs.localBranches
        .map((RefInfo b) => b.shortName)
        .toList(growable: false);

    final String? error = branchNameError(
      _nameController.text,
      existingNames: existingNames,
    );
    final bool canCreate =
        _nameController.text.trim().isNotEmpty &&
        error == null &&
        (_startRef?.isNotEmpty ?? false);

    return GbmDialogShell(
      title: 'New Branch',
      actionId: GbmActionId.branchNewBranch,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Create branch',
          kind: GbmButtonKind.primary,
          onPressed: canCreate ? _submit : null,
        ),
      ],
      // Scrollable, not a bare Column: two checkboxes plus the picker's own
      // 200px list can exceed GbmDialogShell's 560px cap on a short window,
      // and the shell's own `Flexible` does not shrink an unbounded Column
      // for you -- it overflows instead.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '名稱',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            SizedBox(
              height: GbmSpacing.inputHeight,
              child: TextField(
                key: const Key('new-branch-name-field'),
                controller: _nameController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (canCreate) _submit();
                },
                decoration: gbmInputDecoration(
                  colors: colors,
                  hasError: error != null,
                ),
              ),
            ),
            gbmFieldError(colors: colors, error: error),
            const SizedBox(height: GbmSpacing.space3),
            // P6 field-label treatment (spec's G3) -- see
            // add_worktree_dialog.dart's identical comment on '分支'.
            Text(
              '從哪裡分出',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            GbmRefPicker(
              entries: entries,
              selected: _startRef,
              allowCommitHash: true,
              maxListHeight: 200,
              hintText: '可搜尋 branch / tag / commit',
              onSelected: (GbmRefPickerEntry entry) =>
                  setState(() => _startRef = entry.name),
            ),
            const SizedBox(height: GbmSpacing.space2),
            CheckboxListTile(
              value: _checkoutAfter,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '建立後直接 checkout',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (bool? value) =>
                  setState(() => _checkoutAfter = value ?? false),
            ),
            // Absent, not disabled, with none-or-several remotes -- an
            // unreachable checkbox that still shows a remote name it will
            // never use would be more confusing than not offering it.
            if (soleRemote != null)
              CheckboxListTile(
                value: _pushAfterCreate,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '同時 push 並設為 upstream',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '會推送到 $soleRemote。',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
                onChanged: (bool? value) =>
                    setState(() => _pushAfterCreate = value ?? false),
              ),
          ],
        ),
      ),
    );
  }
}
