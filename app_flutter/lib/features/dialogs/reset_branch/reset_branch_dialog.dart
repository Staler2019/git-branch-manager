import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `ResetBranchDialog`
/// (src/app/dialogs/ResetBranchDialog.cpp). Routed as
/// `/repo/:repoId/dialogs/reset-branch`.
class ResetBranchDialogContent extends ConsumerStatefulWidget {
  const ResetBranchDialogContent({
    super.key,
    required this.identity,
    this.target,
  });

  final RepoIdentity identity;

  /// Pre-fills the "Reset to" field. 05-E's "Reset branch to here…" passes
  /// the right-clicked commit's oid; null keeps the dialog's own default of
  /// the current branch, which is what Branch -> Reset… has always opened
  /// with.
  final String? target;

  @override
  ConsumerState<ResetBranchDialogContent> createState() =>
      _ResetBranchDialogContentState();
}

class _ResetBranchDialogContentState
    extends ConsumerState<ResetBranchDialogContent> {
  late final TextEditingController _targetController;
  ResetMode _mode = ResetMode.mixed;

  @override
  void initState() {
    super.initState();
    final RepoSessionState session = ref.read(
      repoSessionProvider(widget.identity),
    );
    _targetController = TextEditingController(
      text: widget.target ?? session.refs.head.branchName,
    );
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return GbmDialogShell(
      title: 'Reset Branch',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Reset',
          kind: GbmButtonKind.primary,
          onPressed: () {
            ref
                .read(repoSessionProvider(widget.identity).notifier)
                .resetTo(_targetController.text.trim(), _mode);
            context.pop();
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Reset to',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          TextField(
            controller: _targetController,
            decoration: const InputDecoration(
              hintText: 'Branch, tag, or commit',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          RadioGroup<ResetMode>(
            groupValue: _mode,
            onChanged: (mode) => setState(() => _mode = mode ?? _mode),
            child: const Column(
              children: <Widget>[
                _ModeOption(
                  mode: ResetMode.soft,
                  label: 'Soft',
                  description:
                      'Move HEAD only; keep the index and work tree as they are.',
                ),
                _ModeOption(
                  mode: ResetMode.mixed,
                  label: 'Mixed',
                  description:
                      'Move HEAD and reset the index; keep the work tree.',
                ),
                _ModeOption(
                  mode: ResetMode.hard,
                  label: 'Hard',
                  description:
                      'Move HEAD and overwrite the index and work tree -- discards uncommitted changes.',
                ),
              ],
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
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

  final ResetMode mode;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return RadioListTile<ResetMode>(
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
