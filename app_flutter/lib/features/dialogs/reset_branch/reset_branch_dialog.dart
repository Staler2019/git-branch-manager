import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';

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
            '重設到',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          SizedBox(
            height: GbmSpacing.inputHeight,
            child: TextField(
              controller: _targetController,
              decoration: gbmInputDecoration(
                colors: colors,
                hintText: 'branch、tag 或 commit',
              ),
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
                  label: 'Soft — 保留檔案與 stage',
                  description: '只移動 HEAD，index 與工作區都不動。',
                ),
                _ModeOption(
                  mode: ResetMode.mixed,
                  label: 'Mixed — 保留檔案，取消 stage',
                  description: '移動 HEAD 並重設 index，工作區不動。',
                ),
                _ModeOption(
                  mode: ResetMode.hard,
                  label: 'Hard — 丟掉檔案變更',
                  description: '移動 HEAD 並覆蓋 index 與工作區，未提交的變更會消失。',
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
