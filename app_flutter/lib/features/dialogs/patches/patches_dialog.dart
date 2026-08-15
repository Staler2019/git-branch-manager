import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of the `PatchExportDialog`/`PatchImportDialog` pair
/// (src/app/dialogs/{ExportPatches,ImportPatches}Dialog.cpp), merged into
/// one tabbed dialog here since both operate on the same "commit <-> patch
/// file" boundary. Routed as `/repo/:repoId/dialogs/patches`.
class PatchesDialogContent extends ConsumerStatefulWidget {
  const PatchesDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<PatchesDialogContent> createState() =>
      _PatchesDialogContentState();
}

class _PatchesDialogContentState extends ConsumerState<PatchesDialogContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  final TextEditingController _exportCommitsController =
      TextEditingController();
  final TextEditingController _exportOutputDirController =
      TextEditingController();

  final TextEditingController _applyFilesController = TextEditingController();
  bool _applyThreeWay = false;
  bool _applyUpdateIndex = false;

  final TextEditingController _importFilesController = TextEditingController();
  bool _importThreeWay = false;

  @override
  void dispose() {
    _tabController.dispose();
    _exportCommitsController.dispose();
    _exportOutputDirController.dispose();
    _applyFilesController.dispose();
    _importFilesController.dispose();
    super.dispose();
  }

  List<String> _lines(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionController notifier = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );

    return GbmDialogShell(
      title: 'Patches',
      width: 640,
      actions: <Widget>[
        GbmButton(label: 'Close', onPressed: () => context.pop()),
      ],
      child: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TabBar(
              controller: _tabController,
              labelColor: colors.textPrimary,
              unselectedLabelColor: colors.textTertiary,
              tabs: const <Widget>[
                Tab(text: 'Export'),
                Tab(text: 'Apply'),
                Tab(text: 'Import'),
              ],
            ),
            const SizedBox(height: GbmSpacing.space3),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _ExportTab(
                    commitsController: _exportCommitsController,
                    outputDirController: _exportOutputDirController,
                    onExport: () {
                      final List<String> commits = _lines(
                        _exportCommitsController.text,
                      );
                      final String outputDir = _exportOutputDirController.text
                          .trim();
                      if (commits.isEmpty || outputDir.isEmpty) return;
                      notifier.exportPatches(commits, outputDir);
                    },
                  ),
                  _ApplyTab(
                    filesController: _applyFilesController,
                    threeWay: _applyThreeWay,
                    updateIndex: _applyUpdateIndex,
                    onThreeWayChanged: (value) =>
                        setState(() => _applyThreeWay = value),
                    onUpdateIndexChanged: (value) =>
                        setState(() => _applyUpdateIndex = value),
                    onApply: () {
                      final List<String> files = _lines(
                        _applyFilesController.text,
                      );
                      if (files.isEmpty) return;
                      notifier.applyPatchFiles(
                        files,
                        threeWay: _applyThreeWay,
                        updateIndex: _applyUpdateIndex,
                      );
                    },
                  ),
                  _ImportTab(
                    filesController: _importFilesController,
                    threeWay: _importThreeWay,
                    onThreeWayChanged: (value) =>
                        setState(() => _importThreeWay = value),
                    onImport: () {
                      final List<String> files = _lines(
                        _importFilesController.text,
                      );
                      if (files.isEmpty) return;
                      notifier.importPatches(files, threeWay: _importThreeWay);
                    },
                    onContinue: () => notifier.continueImport(),
                    onSkip: () => notifier.skipImport(),
                    onAbort: () => notifier.abortImport(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportTab extends StatelessWidget {
  const _ExportTab({
    required this.commitsController,
    required this.outputDirController,
    required this.onExport,
  });

  final TextEditingController commitsController;
  final TextEditingController outputDirController;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Commits (one hex per line, oldest first)',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space1),
        Expanded(
          child: TextField(
            controller: commitsController,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        TextField(
          controller: outputDirController,
          decoration: const InputDecoration(
            hintText: 'Output directory',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        Align(
          alignment: Alignment.centerRight,
          child: GbmButton(
            label: 'Export',
            kind: GbmButtonKind.primary,
            onPressed: onExport,
          ),
        ),
      ],
    );
  }
}

class _ApplyTab extends StatelessWidget {
  const _ApplyTab({
    required this.filesController,
    required this.threeWay,
    required this.updateIndex,
    required this.onThreeWayChanged,
    required this.onUpdateIndexChanged,
    required this.onApply,
  });

  final TextEditingController filesController;
  final bool threeWay;
  final bool updateIndex;
  final ValueChanged<bool> onThreeWayChanged;
  final ValueChanged<bool> onUpdateIndexChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Patch files (one path per line)',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space1),
        Expanded(
          child: TextField(
            controller: filesController,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        CheckboxListTile(
          value: threeWay,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'Fall back to a 3-way merge if the patch does not apply cleanly',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
          ),
          onChanged: (value) => onThreeWayChanged(value ?? false),
        ),
        CheckboxListTile(
          value: updateIndex,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'Also stage the result',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
          ),
          onChanged: (value) => onUpdateIndexChanged(value ?? false),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: GbmButton(
            label: 'Apply',
            kind: GbmButtonKind.primary,
            onPressed: onApply,
          ),
        ),
      ],
    );
  }
}

class _ImportTab extends StatelessWidget {
  const _ImportTab({
    required this.filesController,
    required this.threeWay,
    required this.onThreeWayChanged,
    required this.onImport,
    required this.onContinue,
    required this.onSkip,
    required this.onAbort,
  });

  final TextEditingController filesController;
  final bool threeWay;
  final ValueChanged<bool> onThreeWayChanged;
  final VoidCallback onImport;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Patch files (one path per line, format-patch style)',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space1),
        Expanded(
          child: TextField(
            controller: filesController,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        CheckboxListTile(
          value: threeWay,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'Fall back to a 3-way merge if a patch does not apply cleanly',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
          ),
          onChanged: (value) => onThreeWayChanged(value ?? false),
        ),
        Row(
          children: <Widget>[
            GbmButton(
              label: 'Import',
              kind: GbmButtonKind.primary,
              onPressed: onImport,
            ),
            const Spacer(),
            GbmButton(label: 'Continue', onPressed: onContinue),
            const SizedBox(width: GbmSpacing.space1),
            GbmButton(label: 'Skip', onPressed: onSkip),
            const SizedBox(width: GbmSpacing.space1),
            GbmButton(label: 'Abort', onPressed: onAbort),
          ],
        ),
      ],
    );
  }
}
