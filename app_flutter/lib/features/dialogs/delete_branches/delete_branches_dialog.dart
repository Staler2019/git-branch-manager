import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/branch_deletion_probe.dart';
import '../../../data/models/git_error.dart';
import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_field_kinds.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../branch_deletion_probe_copy.dart';

/// One branch's line in the confirmation list.
@immutable
class DeleteBranchLine {
  const DeleteBranchLine({
    required this.name,
    required this.tip,
    required this.remote,
  });

  final String name;

  /// The tip the refs snapshot shows, empty when it has no such branch. A
  /// change is what makes the dialog read the counts again.
  final String tip;

  /// The remote its upstream lives on, empty when it has none.
  final String remote;

  bool get hasUpstream => remote.isNotEmpty;
}

/// Builds the per-branch lines spec page 13 requires the confirmation to
/// show: 「破壞性批次動作（Delete branches、Drop stashes）的確認 dialog 逐項
/// 列出名稱與未 push 的 commit 數，並區分「本地」與「遠端」兩份清單，不用
/// 一句「刪除 3 個分支？」概括」.
///
/// The count each row draws is not here: it comes from the read the dialog
/// takes (`probeBranchDeletion`), which counted at the tip a forced delete
/// sends. The snapshot's `ahead` is neither that count nor tied to a tip.
///
/// The upstream test is `upstream.isNotEmpty`, **not** `hasTrackingInfo`:
/// the latter mirrors git's `%(upstream:track)`, which is an empty string
/// for a branch exactly in sync with its upstream (see CLAUDE.md's Tier 0c
/// note), so it would wrongly report the most common case as untracked.
///
/// The remote name comes from [remoteBranchParts], never from splitting
/// `upstream` at its first slash -- `upstream` is the *full* ref name
/// (`refs/remotes/origin/x`), so that split yields `"refs"`. That is exactly
/// the live bug tracked as #74 in `delete_branch_dialog.dart`.
List<DeleteBranchLine> deleteBranchLines(List<String> names, RefSnapshot refs) {
  final Map<String, RefInfo> byName = <String, RefInfo>{
    for (final RefInfo r in refs.refs)
      if (r.kind == RefKind.localBranch) r.shortName: r,
  };
  return <DeleteBranchLine>[
    for (final String name in names)
      if (byName[name] case final RefInfo branch)
        DeleteBranchLine(
          name: name,
          tip: branch.target,
          remote: branch.upstream.isEmpty
              ? ''
              : remoteBranchParts(branch.upstream).$1,
        )
      else
        DeleteBranchLine(name: name, tip: '', remote: ''),
  ];
}

/// Confirms a multi-branch delete, listing every branch by name with its
/// unpushed-commit count and splitting local from remote, per spec page 13.
///
/// Routed as `/repo/:repoId/dialogs/delete-branches?names=a,b,c`. Distinct
/// from `delete_branch_dialog.dart`, which is the single-branch 05-B flow
/// with its own branch picker.
class DeleteBranchesDialogContent extends ConsumerStatefulWidget {
  const DeleteBranchesDialogContent({
    super.key,
    required this.identity,
    required this.names,
  });

  final RepoIdentity identity;
  final List<String> names;

  @override
  ConsumerState<DeleteBranchesDialogContent> createState() =>
      _DeleteBranchesDialogContentState();
}

class _DeleteBranchesDialogContentState
    extends ConsumerState<DeleteBranchesDialogContent> {
  bool _alsoDeleteRemote = false;

  /// What each row draws and how it is sent, read for the snapshot tips in
  /// [_readAtTips]. Null while the read is in flight; nothing is sent until
  /// one has landed without an error. A newer read supersedes an older one
  /// by [_readSeq].
  BranchDeletionProbeReply? _probe;
  List<String>? _readAtTips;
  int _readSeq = 0;

  /// Reads every name again whenever the snapshot shows a tip other than
  /// the ones the current read was taken at: a count describes its tip, and
  /// a refresh that moved one makes it stale. Called from build; it changes
  /// no provider state and the reply arrives through `setState` later.
  void _readIfStale(List<DeleteBranchLine> lines) {
    final List<String> tips = <String>[
      for (final DeleteBranchLine l in lines) l.tip,
    ];
    if (listEquals(tips, _readAtTips)) return;
    final int seq = ++_readSeq;
    _probe = null;
    _readAtTips = tips;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .probeBranchDeletion(widget.names)
        .then((BranchDeletionProbeReply reply) {
          if (!mounted || seq != _readSeq) return;
          setState(() => _probe = reply);
        });
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<DeleteBranchLine> lines = deleteBranchLines(
      widget.names,
      session.refs,
    );
    final List<DeleteBranchLine> tracked = lines
        .where((DeleteBranchLine l) => l.hasUpstream)
        .toList();
    _readIfStale(lines);
    final BranchDeletionProbeReply? probe = _probe;
    final GitError? readError = probe?.error;
    final Map<String, BranchDeletionProbe> byName =
        <String, BranchDeletionProbe>{
          if (readError == null)
            for (final BranchDeletionProbe p
                in probe?.probes ?? const <BranchDeletionProbe>[])
              p.name: p,
        };
    final List<DeleteBranchEntry> entries = _entries(lines, byName);
    final int forced = entries.where((DeleteBranchEntry e) => e.force).length;
    // Empty while the read is in flight or after it failed: [byName] is.
    final bool canDelete = entries.isNotEmpty;

    return GbmDialogShell(
      title: 'Delete ${lines.length} branches',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Delete ${lines.length} branches',
          kind: GbmButtonKind.danger,
          onPressed: canDelete ? () => _delete(entries, tracked) : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle(context, '本地分支'),
          for (final DeleteBranchLine line in lines)
            _BranchLineRow(
              name: line.name,
              probe: byName[line.name],
              reading: probe == null,
            ),
          if (readError != null) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            Text(
              branchDeletionProbeFailedText(readError),
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ],
          // P13's per-row numbers are the warning; this line says what they
          // add up to, since confirming no longer meets a refusal.
          if (forced > 0) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            GbmDialogWarnField(message: '其中 $forced 個分支會直接刪除，不再檢查是否已合併。'),
          ],
          if (tracked.isNotEmpty) ...<Widget>[
            const SizedBox(height: GbmSpacing.space3),
            _sectionTitle(context, '遠端分支'),
            for (final DeleteBranchLine line in tracked)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${line.remote}/${line.name}',
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textXs,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            CheckboxListTile(
              value: _alsoDeleteRemote,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '同時刪除遠端分支',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (bool? value) =>
                  setState(() => _alsoDeleteRemote = value ?? false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: GbmSpacing.space1),
    child: Text(
      text,
      style: TextStyle(
        fontSize: GbmTypography.textXs,
        fontWeight: GbmTypography.weightSemibold,
        color: context.gbmColors.textTertiary,
      ),
    ),
  );

  void _delete(
    List<DeleteBranchEntry> entries,
    List<DeleteBranchLine> tracked,
  ) {
    final RepoSessionController notifier = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );
    // One call, not N: gbm_branch_delete takes every name at once, matching
    // `git branch -d`'s own multi-name support -- "a multi-select delete is
    // one operation, not N" (gbm_capi.h). N calls would also emit N
    // OPERATION_FINISHED events against spec page 10's one-background-task
    // rule.
    // Grouped by remote: the remote form runs `git push <remoteName>
    // --delete <names...>`, so a selection spanning two remotes needs one
    // push each. Sent by the controller only once the local delete
    // succeeds, never alongside it.
    final Map<String, List<String>> byRemote = <String, List<String>>{};
    if (_alsoDeleteRemote) {
      for (final DeleteBranchLine line in tracked) {
        byRemote.putIfAbsent(line.remote, () => <String>[]).add(line.name);
      }
    }
    notifier.deleteBranch(
      entries: entries,
      thenDeleteRemote: <RemoteBranchDeletion>[
        for (final MapEntry<String, List<String>> e in byRemote.entries)
          RemoteBranchDeletion(remoteName: e.key, names: e.value),
      ],
    );
    context.pop();
  }

  /// Each line by its own read: plain `-d` where the upstream has every
  /// commit (git compares against that same upstream, so it cannot refuse),
  /// `-D` at the read tip -- never the snapshot's `target` -- where it was
  /// warned about. A line the read found already gone is skipped.
  List<DeleteBranchEntry> _entries(
    List<DeleteBranchLine> lines,
    Map<String, BranchDeletionProbe> byName,
  ) => <DeleteBranchEntry>[
    for (final DeleteBranchLine line in lines)
      if (switch (byName[line.name]) {
            ProbeCounted(unsyncedCount: 0) => DeleteBranchEntry.plain(
              line.name,
            ),
            ProbeCounted(:final String tipOid) ||
            ProbeNoReference(
              :final String tipOid,
            ) => DeleteBranchEntry.forced(line.name, expectedTipOid: tipOid),
            ProbeNotFound() || null => null,
          }
          case final DeleteBranchEntry entry)
        entry,
  ];
}

class _BranchLineRow extends StatelessWidget {
  const _BranchLineRow({
    required this.name,
    required this.probe,
    required this.reading,
  });

  final String name;

  /// This branch's part of the read; null while [reading] or when it failed.
  final BranchDeletionProbe? probe;
  final bool reading;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final BranchDeletionProbe? read = probe;
    final String detail = read != null
        ? branchDeletionProbeText(read)
        : (reading ? '計算中…' : '');
    // Warned about exactly when it will be sent as `-D`.
    final bool warn = switch (read) {
      ProbeCounted(unsyncedCount: 0) => false,
      ProbeCounted() || ProbeNoReference() => true,
      ProbeNotFound() || null => false,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textXs,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          Text(
            detail,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: warn ? colors.warning : colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
