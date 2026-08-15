import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/submodule_info.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `ManageSubmodulesDialog` (src/app/dialogs/
/// ManageSubmodulesDialog.cpp). Routed as
/// `/repo/:repoId/dialogs/manage-submodules`.
class ManageSubmodulesDialogContent extends ConsumerStatefulWidget {
  const ManageSubmodulesDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ManageSubmodulesDialogContent> createState() =>
      _ManageSubmodulesDialogContentState();
}

class _ManageSubmodulesDialogContentState
    extends ConsumerState<ManageSubmodulesDialogContent> {
  bool _addExpanded = false;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(repoSessionProvider(widget.identity).notifier)
          .refreshSubmodules(),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _pathController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<SubmoduleInfo> submodules = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.submodules),
    );
    final RepoSessionController notifier = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );

    return GbmDialogShell(
      title: 'Manage Submodules',
      width: 680,
      actions: <Widget>[
        GbmButton(
          label: 'Update All',
          onPressed: () => notifier.updateSubmodules(init: true),
        ),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: _addExpanded ? 'Cancel Add' : 'Add…',
          onPressed: () => setState(() => _addExpanded = !_addExpanded),
        ),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Close',
          kind: GbmButtonKind.primary,
          onPressed: () => context.pop(),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_addExpanded) ...<Widget>[
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'Repository URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                hintText: 'Path (leave empty to derive from URL)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            TextField(
              controller: _branchController,
              decoration: const InputDecoration(
                hintText: 'Branch (optional)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            Align(
              alignment: Alignment.centerRight,
              child: GbmButton(
                label: 'Add',
                kind: GbmButtonKind.primary,
                onPressed: () {
                  final String url = _urlController.text.trim();
                  if (url.isEmpty) return;
                  notifier.addSubmodule(
                    url,
                    path: _pathController.text.trim(),
                    branch: _branchController.text.trim(),
                  );
                  setState(() {
                    _addExpanded = false;
                    _urlController.clear();
                    _pathController.clear();
                    _branchController.clear();
                  });
                },
              ),
            ),
            const Divider(height: GbmSpacing.space4 * 2),
          ],
          SizedBox(
            height: 300,
            child: submodules.isEmpty
                ? Center(
                    child: Text(
                      'No submodules',
                      style: TextStyle(color: colors.textTertiary),
                    ),
                  )
                : ListView(
                    children: <Widget>[
                      for (final submodule in submodules)
                        _SubmoduleRow(
                          submodule: submodule,
                          onUpdate: () => notifier.updateSubmodules(
                            paths: <String>[submodule.path],
                            init: true,
                          ),
                          onSync: () => notifier.syncSubmodules(
                            paths: <String>[submodule.path],
                          ),
                          onDeinit: () => notifier.deinitSubmodules(
                            paths: <String>[submodule.path],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SubmoduleRow extends StatelessWidget {
  const _SubmoduleRow({
    required this.submodule,
    required this.onUpdate,
    required this.onSync,
    required this.onDeinit,
  });

  final SubmoduleInfo submodule;
  final VoidCallback onUpdate;
  final VoidCallback onSync;
  final VoidCallback onDeinit;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space1,
        vertical: GbmSpacing.space2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      submodule.path,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textPrimary,
                        fontWeight: GbmTypography.weightMedium,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: GbmSpacing.space1),
                    Text(
                      '(${_stateLabel(submodule.state)})',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: _stateColor(submodule.state, colors),
                      ),
                    ),
                  ],
                ),
                Text(
                  submodule.url,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUpdate,
            child: Text(
              'Update',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: onSync,
            child: Text(
              'Sync',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: onDeinit,
            child: Text(
              'Deinit',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stateLabel(SubmoduleState state) => switch (state) {
    SubmoduleState.notInitialized => 'not initialized',
    SubmoduleState.upToDate => 'up to date',
    SubmoduleState.modified => 'modified',
    SubmoduleState.conflicted => 'conflicted',
  };

  Color _stateColor(SubmoduleState state, GbmColors colors) => switch (state) {
    SubmoduleState.notInitialized => colors.textTertiary,
    SubmoduleState.upToDate => colors.textTertiary,
    SubmoduleState.modified => colors.accent,
    SubmoduleState.conflicted => colors.danger,
  };
}
