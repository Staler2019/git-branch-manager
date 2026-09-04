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

/// The Dart analog of `CherryPickDialog` (src/app/dialogs/
/// CherryPickDialog.cpp). Routed as `/repo/:repoId/dialogs/cherry-pick`.
/// `initialCommitHex` pre-fills the commit list when opened from a graph
/// row's context menu (not yet wired -- the graph has no context menu
/// until a later milestone); an empty value leaves the field for manual
/// entry.
class CherryPickDialogContent extends ConsumerStatefulWidget {
  const CherryPickDialogContent({
    super.key,
    required this.identity,
    this.initialCommitHex = '',
  });

  final RepoIdentity identity;
  final String initialCommitHex;

  @override
  ConsumerState<CherryPickDialogContent> createState() =>
      _CherryPickDialogContentState();
}

class _CherryPickDialogContentState
    extends ConsumerState<CherryPickDialogContent> {
  late final TextEditingController _commitsController;
  bool _noCommit = false;
  bool _stashFirst = false;

  @override
  void initState() {
    super.initState();
    _commitsController = TextEditingController(text: widget.initialCommitHex);
  }

  @override
  void dispose() {
    _commitsController.dispose();
    super.dispose();
  }

  List<String> get _commitHexes => _commitsController.text
      .split(RegExp(r'[\s,]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return GbmDialogShell(
      title: 'Cherry-pick Commits',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Cherry-pick',
          kind: GbmButtonKind.primary,
          onPressed: _commitHexes.isEmpty
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .cherryPick(
                        _commitHexes,
                        noCommit: _noCommit,
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
            '套用這些 commit（依序）',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          TextField(
            controller: _commitsController,
            maxLines: 3,
            decoration: gbmMultilineInputDecoration(
              colors: colors,
              hintText: '以空白或換行分隔，舊的在前',
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          CheckboxListTile(
            value: _noCommit,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              '不自動 commit（-n，套完停在工作區）',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            onChanged: (value) => setState(() => _noCommit = value ?? false),
          ),
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
            onChanged: (value) => setState(() => _stashFirst = value ?? false),
          ),
        ],
      ),
    );
  }
}
