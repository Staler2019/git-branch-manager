import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../../../widgets/gbm_ref_read_only_field.dart';

/// git's own default title for merging [source] into [currentBranch] --
/// git is the authority; this only copies its rule so the dialog can show
/// the message before git runs. Measured on git 2.56 (2026-10-08, see
/// docs/claude-design-demo/merge-rebase-dialogs-spec.html ⑦): the
/// `into <branch>` suffix is omitted for `main` and `master`, and a
/// remote-tracking source is named as one.
String _defaultMergeTitle({
  required String source,
  required bool sourceIsRemote,
  required String currentBranch,
}) {
  final String kind = sourceIsRemote ? 'remote-tracking branch' : 'branch';
  final bool omitsDestination =
      currentBranch.isEmpty ||
      currentBranch == 'main' ||
      currentBranch == 'master';
  return omitsDestination
      ? "Merge $kind '$source'"
      : "Merge $kind '$source' into $currentBranch";
}

/// The Dart analog of `MergeDialog` (src/app/dialogs/MergeDialog.cpp).
/// Routed as `/repo/:repoId/dialogs/merge`.
class MergeDialogContent extends ConsumerStatefulWidget {
  const MergeDialogContent({super.key, required this.identity, this.source});

  final RepoIdentity identity;

  /// The branch to merge, when the caller already knows it (05-B's "Merge
  /// into current"). See RoutePaths.mergeDialogFor.
  final String? source;

  @override
  ConsumerState<MergeDialogContent> createState() => _MergeDialogContentState();
}

class _MergeDialogContentState extends ConsumerState<MergeDialogContent> {
  late final TextEditingController _messageController;
  String? _target;

  /// What the message box was last filled with automatically. A new source
  /// replaces the message only while the box still holds exactly this --
  /// the moment the user types their own, it is theirs.
  String _lastAutofill = '';
  MergeMode _mode = MergeMode.noFastForward;
  bool _stashFirst = false;

  /// `source|HEAD oid|source oid` of the last squash preview asked for, and
  /// of the one already re-asked after a stale reply -- the second is what
  /// stops a reply that never matches from looping requests forever.
  String? _requestedKey;
  String? _retriedKey;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _target = widget.source;
    _syncMessage(ref.read(repoSessionProvider(widget.identity)));
  }

  bool _isRemote(RepoSessionState session, String name) =>
      session.refs.remoteBranches.any((RefInfo b) => b.shortName == name);

  String _sourceTip(RepoSessionState session, String name) {
    for (final RefInfo b in <RefInfo>[
      ...session.refs.localBranches,
      ...session.refs.remoteBranches,
    ]) {
      if (b.shortName == name) return b.target;
    }
    return '';
  }

  /// The squash preview, but only if it answers the current pick against
  /// the refs as they are now ([SquashMessagePreview.isCurrentFor]).
  SquashMessagePreview? _currentPreview(RepoSessionState session) {
    final String? target = _target;
    final SquashMessagePreview? preview = session.squashMessagePreview;
    if (target == null || preview == null) return null;
    return preview.isCurrentFor(target, session.refs) ? preview : null;
  }

  /// A reply that could not be built still answers the pick: Merge is
  /// allowed, with whatever the user typed (empty leaves it only staged).
  bool _previewFailedFor(RepoSessionState session) {
    final SquashMessagePreview? preview = session.squashMessagePreview;
    return preview != null && preview.failed && preview.source == _target;
  }

  /// What the box should hold right now if the user has not written their
  /// own: git's squash message in Squash mode (empty until it arrives), the
  /// merge title otherwise.
  String _autofillFor(RepoSessionState session) {
    final String? target = _target;
    if (target == null) return '';
    if (_mode == MergeMode.squash) {
      return _currentPreview(session)?.message ?? '';
    }
    return _defaultMergeTitle(
      source: target,
      sourceIsRemote: _isRemote(session, target),
      currentBranch: session.refs.head.branchName,
    );
  }

  /// Replaces the message only while the box still holds exactly the last
  /// autofill -- the moment the user types their own, it is theirs.
  void _syncMessage(RepoSessionState session) {
    if (_messageController.text != _lastAutofill) return;
    _lastAutofill = _autofillFor(session);
    _messageController.text = _lastAutofill;
  }

  /// Asks core for the squash message whenever the pick, HEAD or the source
  /// tip differs from what was last asked. Deferred to after the frame: this
  /// runs from a provider listener, and a provider write must not happen
  /// inside the notification that triggered it ([FLU-postframe-no-frame]:
  /// paired with ensureVisualUpdate so the callback actually runs).
  void _ensureSquashRequested(RepoSessionState session, {bool stale = false}) {
    final String? target = _target;
    if (_mode != MergeMode.squash || target == null) return;
    if (_currentPreview(session) != null) return;
    final String key =
        '$target|${session.refs.head.target}|${_sourceTip(session, target)}';
    if (stale) {
      if (_retriedKey == key) return;
      _retriedKey = key;
    } else if (_requestedKey == key) {
      return;
    }
    _requestedKey = key;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(repoSessionProvider(widget.identity).notifier)
          .requestSquashMessage(target);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Ruling ②: local branches other than the current one, plus every
  /// remote-tracking branch -- merging `origin/main` is an ordinary request.
  List<GbmRefPickerEntry> _entries(RepoSessionState session) {
    final String head = session.refs.head.branchName;
    return <GbmRefPickerEntry>[
      for (final RefInfo b in session.refs.localBranches)
        if (b.shortName != head)
          GbmRefPickerEntry(name: b.shortName, kind: GbmRefKind.localBranch),
      for (final RefInfo b in session.refs.remoteBranches)
        GbmRefPickerEntry(name: b.shortName, kind: GbmRefKind.remoteBranch),
    ];
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final String currentBranch = session.refs.head.branchName;
    final String? source = widget.source;

    // A squash preview arriving, or HEAD / the source tip moving, re-syncs the
    // box and, when the reply no longer matches, asks again.
    ref.listen<RepoSessionState>(repoSessionProvider(widget.identity), (
      RepoSessionState? previous,
      RepoSessionState next,
    ) {
      if (_mode != MergeMode.squash) return;
      final bool replyArrived =
          next.squashMessagePreview != null &&
          next.squashMessagePreview != previous?.squashMessagePreview;
      if (next.refs != previous?.refs || replyArrived) {
        setState(() => _syncMessage(next));
        // A failed reply is an answer, not a stale one: asking again would
        // only fail again.
        _ensureSquashRequested(
          next,
          stale:
              replyArrived &&
              next.squashMessagePreview?.failed != true &&
              _currentPreview(next) == null,
        );
      }
    });
    final bool squashReady =
        _mode != MergeMode.squash ||
        _previewFailedFor(session) ||
        (_currentPreview(session)?.message.isNotEmpty ?? false);

    return GbmDialogShell(
      title: 'Merge Branch',
      actionId: GbmActionId.branchMergeIntoCurrent,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Merge',
          kind: GbmButtonKind.primary,
          // In Squash mode, only once git's message for *these* refs is in
          // the box -- or nothing could be built and the user is on their
          // own. An empty current preview is "nothing to squash".
          onPressed: _target == null || !squashReady
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .mergeBranch(
                        _target!,
                        _mode,
                        // A squash message is git's own text, indented body
                        // and all; git's commit cleanup handles its edges.
                        message: _mode == MergeMode.squash
                            ? _messageController.text
                            : _messageController.text.trim(),
                        stashFirst: _stashFirst,
                      );
                  context.pop();
                },
        ),
      ],
      // Scrolled, like Add worktree's, because the content genuinely exceeds
      // GbmDialogShell's 560px cap: 「合入 <branch>」 wraps onto a second
      // line for any branch name of ordinary length and the Column
      // overflows. Every child here is non-flex, so nothing inside it can
      // give way ([FLU-renderflex-non-flex-first]) -- an Expanded would only
      // trade the overflow for a collapsed child.
      //
      // It was overflowing by 11px with the English copy too, unmeasured and
      // untested; the shorter Chinese copy hid it by accident one commit ago.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // DLGS: `focus 來源分支` then `ro 合入`. A source the caller
            // already chose is drawn `ro` instead -- re-asking for what the
            // user just clicked is the defect this replaced.
            if (source != null)
              GbmRefReadOnlyField(
                label: '來源分支',
                name: source,
                kind: _isRemote(session, source)
                    ? GbmRefKind.remoteBranch
                    : GbmRefKind.localBranch,
              )
            else ...<Widget>[
              Text(
                '來源分支',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: GbmSpacing.space1),
              GbmRefPicker(
                entries: _entries(session),
                selected: _target,
                autofocus: true,
                hintText: '搜尋分支',
                emptyMessage: '沒有可以合入的分支。',
                maxListHeight: 160,
                onSelected: (GbmRefPickerEntry entry) {
                  setState(() {
                    _target = entry.name;
                    _syncMessage(session);
                  });
                  _ensureSquashRequested(session);
                },
              ),
            ],
            const SizedBox(height: GbmSpacing.space2),
            GbmRefReadOnlyField(
              label: '合入',
              name: currentBranch,
              kind: GbmRefKind.localBranch,
            ),
            const SizedBox(height: GbmSpacing.space3),
            RadioGroup<MergeMode>(
              groupValue: _mode,
              onChanged: (mode) {
                setState(() {
                  _mode = mode ?? _mode;
                  _syncMessage(session);
                });
                _ensureSquashRequested(session);
              },
              child: const Column(
                children: <Widget>[
                  _ModeOption(
                    mode: MergeMode.fastForwardOnly,
                    // Not the spec's second radio. `MergeMode.fastForwardOnly`
                    // is `--ff-only`, which *fails* when a merge commit would be
                    // needed; the spec's 「Fast-forward 可行時不建 commit」 is
                    // plain `--ff`, a mode this app does not have. Transcribing
                    // that wording onto this value would relabel the behaviour,
                    // so the copy is composed in the spec's voice instead.
                    label: '只允許 fast-forward',
                    description: '無法 fast-forward 時直接失敗，不建 merge commit。',
                  ),
                  _ModeOption(
                    mode: MergeMode.noFastForward,
                    label: 'Merge commit（保留分支形狀）',
                    description: '即使可以 fast-forward，也一定建立 merge commit。',
                  ),
                  _ModeOption(
                    mode: MergeMode.squash,
                    label: 'Squash 成一筆',
                    description: '把來源的變更合成一筆一般 commit，不記錄 merge commit。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
            Text(
              'Commit 訊息',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            TextField(
              controller: _messageController,
              style: const TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textSm,
              ),
              // 02-C: DLGS's hint 「squash 時改為多行欄位並帶入來源 commit 摘要」.
              minLines: _mode == MergeMode.squash ? 4 : null,
              maxLines: _mode == MergeMode.squash ? 8 : 2,
              decoration: gbmMultilineInputDecoration(
                colors: colors,
                hintText: "Merge branch '…'",
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            CheckboxListTile(
              value: _stashFirst,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '先 stash 未提交的變更',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (value) =>
                  setState(() => _stashFirst = value ?? false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.label,
    required this.description,
  });

  final MergeMode mode;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return RadioListTile<MergeMode>(
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
