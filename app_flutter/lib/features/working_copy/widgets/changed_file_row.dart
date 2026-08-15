import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/working_copy_status.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';

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
      label:
          '${entry.path}, ${_statusDescription(entry)}${checked ? ', staged' : ''}',
      child: GestureDetector(
        onSecondaryTapDown: (details) => _openContextMenu(context, details),
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
                    label: checked
                        ? 'Unstage ${entry.path}'
                        : 'Stage ${entry.path}',
                    child: Checkbox(
                      value: checked,
                      onChanged: (_) => onCheckToggle(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.path,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _statusLabel(entry),
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: _statusColor(entry, colors),
                  ),
                ),
                if (onBlame != null ||
                    onFileHistory != null ||
                    onLineHistory != null ||
                    onDiscard != null)
                  _FileActionsMenu(
                    onBlame: onBlame,
                    onFileHistory: onFileHistory,
                    onLineHistory: onLineHistory,
                    onDiscard: onDiscard,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `ctxItemsFor('unstaged-file'|'staged-file')` from gbm_context_menus.dart's
  /// 05-F (File in working copy), scoped to what this row already has real
  /// callbacks for. "Open file" has no launcher wired anywhere in this app yet,
  /// and no OS-reveal launcher or per-file terminal launcher are wired (per
  /// repo_list_tile's documented omissions), so those are left off rather than
  /// pointed at nothing. Blame/File History/Line History are real, useful
  /// features specific to this app and stay in the separate [_FileActionsMenu]
  /// trailing button; folding them into a right-click "More actions" submenu
  /// is deferred until `GbmMenuItem.submenu`'s flyout actually renders its
  /// children (currently data-only -- see gbm_menu.dart's doc comment).
  void _openContextMenu(BuildContext context, TapDownDetails details) {
    showGbmContextMenu(context, details.globalPosition, <GbmMenuItem>[
      GbmMenuItem(
        label: checked ? 'Unstage file' : 'Stage file',
        icon: checked ? Icons.remove : Icons.add,
        onTap: onCheckToggle,
      ),
      GbmMenuItem(
        label: 'View diff',
        icon: Icons.difference_outlined,
        onTap: onTap,
      ),
      GbmMenuItem(
        label: 'Copy path',
        icon: Icons.copy,
        onTap: () => Clipboard.setData(ClipboardData(text: entry.path)),
      ),
      if (onDiscard != null) ...<GbmMenuItem>[
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Discard changes',
          icon: Icons.delete_outline,
          danger: true,
          onTap: onDiscard!,
        ),
      ],
    ]);
  }

  String _statusDescription(WorkingCopyEntry entry) {
    if (entry.untracked) return 'untracked';
    final FileChangeKind kind = entry.staged
        ? entry.indexStatus
        : entry.worktreeStatus;
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
    final FileChangeKind kind = entry.staged
        ? entry.indexStatus
        : entry.worktreeStatus;
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
    final FileChangeKind kind = entry.staged
        ? entry.indexStatus
        : entry.worktreeStatus;
    return switch (kind) {
      FileChangeKind.added => colors.success,
      FileChangeKind.deleted => colors.danger,
      _ => colors.textTertiary,
    };
  }
}

/// The trailing "more" button offering Blame/File History/Line
/// History/Discard for a [ChangedFileRow] -- a button-anchored flat
/// [showGbmMenu], mirroring `tab_row.dart`'s `_MoreMenu._open` rather than
/// Material's `PopupMenuButton` (see that widget's doc comment for why).
class _FileActionsMenu extends StatelessWidget {
  const _FileActionsMenu({
    this.onBlame,
    this.onFileHistory,
    this.onLineHistory,
    this.onDiscard,
  });

  final VoidCallback? onBlame;
  final VoidCallback? onFileHistory;
  final VoidCallback? onLineHistory;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Builder(
      builder: (buttonContext) => IconButton(
        tooltip: 'File actions',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert, size: 16, color: colors.textTertiary),
        onPressed: () => _open(buttonContext),
      ),
    );
  }

  void _open(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    showGbmMenu(
      buttonContext,
      position: position,
      items: <GbmMenuItem>[
        if (onBlame != null) GbmMenuItem(label: 'Blame…', onTap: onBlame!),
        if (onFileHistory != null)
          GbmMenuItem(label: 'File History…', onTap: onFileHistory!),
        if (onLineHistory != null)
          GbmMenuItem(label: 'Line History…', onTap: onLineHistory!),
        if (onDiscard != null)
          GbmMenuItem(
            label: 'Discard changes',
            danger: true,
            onTap: onDiscard!,
          ),
      ],
    );
  }
}
