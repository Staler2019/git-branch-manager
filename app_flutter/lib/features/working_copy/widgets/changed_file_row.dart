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
  });

  final WorkingCopyEntry entry;
  final bool checked;
  final bool selected;
  final VoidCallback onCheckToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: GbmSpacing.rowHeightCompact,
        color: selected ? colors.surfaceSelected : null,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 24,
              child: Checkbox(value: checked, onChanged: (_) => onCheckToggle(), visualDensity: VisualDensity.compact),
            ),
            Expanded(
              child: Text(
                entry.path,
                style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(_statusLabel(entry), style: TextStyle(fontSize: GbmTypography.textXs, color: _statusColor(entry, colors))),
          ],
        ),
      ),
    );
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
