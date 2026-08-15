import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

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
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Merge into $currentBranch',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          DropdownButtonFormField<String>(
            initialValue: _target,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: 'Branch to merge from',
              isDense: true,
              border: OutlineInputBorder(),
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
          const SizedBox(height: GbmSpacing.space3),
          RadioGroup<MergeMode>(
            groupValue: _mode,
            onChanged: (mode) => setState(() => _mode = mode ?? _mode),
            child: const Column(
              children: <Widget>[
                _ModeOption(
                  mode: MergeMode.fastForwardOnly,
                  label: 'Fast-forward only',
                  description:
                      'Fail unless the current branch can be fast-forwarded.',
                ),
                _ModeOption(
                  mode: MergeMode.noFastForward,
                  label: 'No fast-forward',
                  description:
                      'Always create a merge commit, even if a fast-forward is possible.',
                ),
                _ModeOption(
                  mode: MergeMode.squash,
                  label: 'Squash',
                  description:
                      'Combine changes without recording a merge commit.',
                ),
              ],
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          TextField(
            controller: _messageController,
            enabled: _mode != MergeMode.squash,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Merge commit message (optional)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          CheckboxListTile(
            value: _stashFirst,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Stash uncommitted changes first',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            onChanged: (value) => setState(() => _stashFirst = value ?? false),
          ),
        ],
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
