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

/// The Dart analog of `MergeDialog` (src/app/dialogs/MergeDialog.cpp).
/// Routed as `/repo/:repoId/dialogs/merge`.
class MergeDialogContent extends ConsumerStatefulWidget {
  const MergeDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<MergeDialogContent> createState() => _MergeDialogContentState();
}

class _MergeDialogContentState extends ConsumerState<MergeDialogContent> {
  late final TextEditingController _messageController;
  String? _target;
  MergeMode _mode = MergeMode.noFastForward;
  bool _stashFirst = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
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
    final List<RefInfo> candidates = session.refs.localBranches
        .where((b) => b.shortName != currentBranch)
        .toList(growable: false);

    return GbmDialogShell(
      title: 'Merge Branch',
      actionId: GbmActionId.branchMergeIntoCurrent,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Merge',
          kind: GbmButtonKind.primary,
          onPressed: _target == null
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .mergeBranch(
                        _target!,
                        _mode,
                        message: _messageController.text.trim(),
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
            Text(
              '合入 $currentBranch',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            SizedBox(
              height: GbmSpacing.inputHeight,
              child: DropdownButtonFormField<String>(
                initialValue: _target,
                isExpanded: true,
                decoration: gbmInputDecoration(
                  colors: colors,
                  hintText: '來源分支',
                ),
                items: <DropdownMenuItem<String>>[
                  for (final branch in candidates)
                    DropdownMenuItem(
                      value: branch.shortName,
                      child: Text(branch.shortName),
                    ),
                ],
                onChanged: (value) => setState(() => _target = value),
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
            RadioGroup<MergeMode>(
              groupValue: _mode,
              onChanged: (mode) => setState(() => _mode = mode ?? _mode),
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
                    description: '把變更併進來，但不記錄 merge commit。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
            TextField(
              controller: _messageController,
              enabled: _mode != MergeMode.squash,
              maxLines: 2,
              decoration: gbmMultilineInputDecoration(
                colors: colors,
                hintText: 'Commit 訊息（可留空）',
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
