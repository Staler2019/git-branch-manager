import 'package:flutter/material.dart';

import '../../../data/models/working_copy_status.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// One row in the staged/unstaged/untracked file lists. The checkbox
/// stages/unstages; tapping the row itself selects it for the diff pane --
/// the same split Fork's (and the Qt app's) working-copy view uses.
class ChangedFileRow extends StatelessWidget {
  const ChangedFileRow({
    super.key,
    required this.entry,
    required this.checked,
    required this.selected,
    required this.onCheckToggle,
    required this.onTap,
    this.onBlame,
    this.onFileHistory,
    this.onLineHistory,
    this.onDiscard,
  });

  final WorkingCopyEntry entry;
  final bool checked;
  final bool selected;
  final VoidCallback onCheckToggle;
  final VoidCallback onTap;
  /// When set, a trailing "more" menu offers Blame/File History/Line
  /// History for this file -- see `working_copy_view.dart`'s wiring of
  /// these into the M6 dialog routes.
  final VoidCallback? onBlame;
  final VoidCallback? onFileHistory;
  final VoidCallback? onLineHistory;
  /// `git restore` (unstaged/work-tree discard) for this file -- see
  /// `working_copy_view.dart`'s wiring into
  /// `RepoSessionController.restorePaths`. Only offered for unstaged
  /// entries (there is no "discard" for what's already staged, only
  /// unstage, which the checkbox already does).
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Semantics(
      label: '${entry.path}, ${_statusDescription(entry)}${checked ? ', staged' : ''}',
      child: InkWell(
      onTap: onTap,
      child: Container(
        height: GbmSpacing.rowHeightCompact,
        color: selected ? colors.surfaceSelected : null,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 24,
              child: Semantics(
                label: checked ? 'Unstage ${entry.path}' : 'Stage ${entry.path}',
                child: Checkbox(value: checked, onChanged: (_) => onCheckToggle(), visualDensity: VisualDensity.compact),
              ),
            ),
            Expanded(
              child: Text(
                entry.path,
                style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(_statusLabel(entry), style: TextStyle(fontSize: GbmTypography.textXs, color: _statusColor(entry, colors))),
            if (onBlame != null || onFileHistory != null || onLineHistory != null || onDiscard != null)
              PopupMenuButton<VoidCallback>(
                tooltip: 'File actions',
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert, size: 16, color: colors.textTertiary),
                onSelected: (action) => action(),
                itemBuilder: (context) => <PopupMenuEntry<VoidCallback>>[
                  if (onBlame != null) PopupMenuItem<VoidCallback>(value: onBlame, child: const Text('Blame…')),
                  if (onFileHistory != null)
                    PopupMenuItem<VoidCallback>(value: onFileHistory, child: const Text('File History…')),
                  if (onLineHistory != null)
                    PopupMenuItem<VoidCallback>(value: onLineHistory, child: const Text('Line History…')),
                  if (onDiscard != null)
                    PopupMenuItem<VoidCallback>(
                      value: onDiscard,
                      child: Text('Discard Changes', style: TextStyle(color: colors.danger)),
                    ),
                ],
              ),
          ],
        ),
      ),
      ),
    );
  }

  String _statusDescription(WorkingCopyEntry entry) {
    if (entry.untracked) return 'untracked';
    final FileChangeKind kind = entry.staged ? entry.indexStatus : entry.worktreeStatus;
    return switch (kind) {
      FileChangeKind.added => 'added',
      FileChangeKind.deleted => 'deleted',
      FileChangeKind.renamed => 'renamed',
      FileChangeKind.copied => 'copied',
      FileChangeKind.typeChanged => 'type changed',
      FileChangeKind.modeChanged => 'mode changed',
      FileChangeKind.modified => 'modified',
    };
  }

  String _statusLabel(WorkingCopyEntry entry) {
    if (entry.untracked) return 'U';
    final FileChangeKind kind = entry.staged ? entry.indexStatus : entry.worktreeStatus;
    return switch (kind) {
      FileChangeKind.added => 'A',
      FileChangeKind.deleted => 'D',
      FileChangeKind.renamed => 'R',
      FileChangeKind.copied => 'C',
      FileChangeKind.typeChanged => 'T',
      FileChangeKind.modeChanged => 'M',
      FileChangeKind.modified => 'M',
    };
  }

  Color _statusColor(WorkingCopyEntry entry, GbmColors colors) {
    if (entry.untracked) return colors.textTertiary;
    final FileChangeKind kind = entry.staged ? entry.indexStatus : entry.worktreeStatus;
    return switch (kind) {
      FileChangeKind.added => colors.success,
      FileChangeKind.deleted => colors.danger,
      _ => colors.textTertiary,
    };
  }
}
