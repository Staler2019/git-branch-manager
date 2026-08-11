import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/working_copy_status.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart' show WorkingCopyDiffReply;
import '../../data/repositories/working_copy_repository.dart' as wc;
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../diff/diff_page.dart';
import '../workspace/workspace_screen.dart' show repoIdForRoute;
import 'widgets/changed_file_row.dart';

/// Changed-file list (staged/unstaged/untracked) + diff pane + commit box.
/// The Dart analog of `WorkingCopyView` (src/app/views/pages/
/// WorkingCopyView.cpp). Route `/repo/:repoId/working-copy`.
class WorkingCopyView extends ConsumerStatefulWidget {
  const WorkingCopyView({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<WorkingCopyView> createState() => _WorkingCopyViewState();
}

class _WorkingCopyViewState extends ConsumerState<WorkingCopyView> {
  String? _selectedPath;
  bool _selectedStaged = false;
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WorkingCopyStatus status = ref.watch(wc.repoWorkingCopyStatusProvider(widget.identity));
    final WorkingCopyDiffReply? diffReply = ref.watch(wc.repoLastDiffProvider(widget.identity));
    final GbmColors colors = context.gbmColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: status.isClean
                    ? Center(child: Text('No changes', style: TextStyle(color: colors.textTertiary)))
                    : ListView(
                        children: <Widget>[
                          if (status.staged.isNotEmpty) _sectionHeader(context, 'STAGED'),
                          for (final entry in status.staged) _rowFor(entry, staged: true),
                          if (status.unstaged.isNotEmpty) _sectionHeader(context, 'UNSTAGED'),
                          for (final entry in status.unstaged) _rowFor(entry, staged: false),
                          if (status.untrackedFiles.isNotEmpty) _sectionHeader(context, 'UNTRACKED'),
                          for (final entry in status.untrackedFiles.where((e) => !e.hasUnstagedChange))
                            _rowFor(entry, staged: false),
                        ],
                      ),
              ),
              _CommitBox(
                enabled: status.staged.isNotEmpty,
                controller: _messageController,
                onCommit: () {
                  final String message = _messageController.text.trim();
                  if (message.isEmpty) return;
                  wc.commitChanges(ref, widget.identity, message);
                  _messageController.clear();
                },
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: colors.borderSubtle),
        Expanded(
          child: _selectedPath == null
              ? Center(child: Text('Select a file', style: TextStyle(color: colors.textTertiary)))
              : (diffReply != null && diffReply.path == _selectedPath && diffReply.staged == _selectedStaged)
              ? DiffPage(diff: diffReply.diff)
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(GbmSpacing.space3, GbmSpacing.space2, GbmSpacing.space3, GbmSpacing.space1),
      child: Text(
        label,
        style: TextStyle(fontSize: GbmTypography.textXs, fontWeight: GbmTypography.weightSemibold, color: colors.textTertiary, letterSpacing: 0.5),
      ),
    );
  }

  Widget _rowFor(WorkingCopyEntry entry, {required bool staged}) {
    final String repoId = repoIdForRoute(widget.identity);
    return ChangedFileRow(
      entry: entry,
      checked: staged,
      selected: _selectedPath == entry.path && _selectedStaged == staged,
      onCheckToggle: () {
        if (staged) {
          wc.unstageFiles(ref, widget.identity, <String>[entry.path]);
        } else {
          wc.stageFiles(ref, widget.identity, <String>[entry.path]);
        }
      },
      onTap: () {
        setState(() {
          _selectedPath = entry.path;
          _selectedStaged = staged;
        });
        wc.requestWorkingCopyDiff(ref, widget.identity, entry.path, staged: staged);
      },
      onBlame: () => context.push(RoutePaths.blameDialogFor(repoId, path: entry.path)),
      onFileHistory: () => context.push(RoutePaths.fileHistoryDialogFor(repoId, path: entry.path)),
      onLineHistory: () => context.push(RoutePaths.lineHistoryDialogFor(repoId, path: entry.path)),
    );
  }
}

class _CommitBox extends StatelessWidget {
  const _CommitBox({required this.enabled, required this.controller, required this.onCommit});

  final bool enabled;
  final TextEditingController controller;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      padding: const EdgeInsets.all(GbmSpacing.space3),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.borderSubtle))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: controller,
            enabled: enabled,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Commit message', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: GbmSpacing.space2),
          GbmButton(label: 'Commit', kind: GbmButtonKind.primary, onPressed: enabled ? onCommit : null),
        ],
      ),
    );
  }
}
