import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/parsed_diff.dart';
import '../../data/repositories/file_list_view_mode_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/file_list_mode_switcher.dart';
import '../../widgets/file_list_mode_toggle_button.dart';
import '../../widgets/gbm_row.dart';
import '../../widgets/split_pane.dart';
import '../diff/diff_page.dart';

/// The 「檔案清單 + diff（唯讀）」 detail column several P19 `PANELSPEC` rows
/// share -- manage-stashes names it verbatim, and patches ("patch 內容 diff
/// 預覽") and file-history ("逐版 diff（唯讀）") are the same shape.
///
/// It exists because [DiffPage] alone is **not** a 檔案清單: for a
/// non-binary file it renders that file's hunks and no header at all, so a
/// multi-file diff arrives as one unlabelled run of hunks. That was found by
/// asserting the file path in a widget test rather than by reading the
/// class, and it is the reason this wrapper is a widget instead of a
/// one-line `DiffPage(...)` at each call site.
///
/// The list honours the shared [fileListViewModeProvider] (spec page 03 item
/// 10's one setting, which Tier 0e extended across History / Compare /
/// Conflict) rather than hardcoding a flat list -- the mistake Tier 0e
/// existed to fix.
///
/// Read-only by construction: [DiffPage] itself is now read-only -- staging
/// moved to `features/diff/scoped_diff_view.dart` when spec P03's 變體 B
/// replaced per-line checkboxes with per-scope cards -- so no staging or
/// discarding is reachable from a panel detail pane.
class PanelFileDiffDetail extends ConsumerStatefulWidget {
  const PanelFileDiffDetail({
    super.key,
    required this.diff,
    required this.storageId,
  });

  final ParsedDiff diff;

  /// Distinguishes this pane's file-list/diff splitter position from every
  /// other panel's, same contract as [GbmPanelTabShell.storageId].
  final String storageId;

  @override
  ConsumerState<PanelFileDiffDetail> createState() =>
      _PanelFileDiffDetailState();
}

class _PanelFileDiffDetailState extends ConsumerState<PanelFileDiffDetail> {
  /// `displayPath` rather than an index: a new diff for the same subject
  /// (re-requested after an apply, say) can reorder or drop files, and an
  /// index would then silently point at a different file.
  String? _selectedPath;

  DiffFile? _resolveSelection() {
    final List<DiffFile> files = widget.diff.files;
    if (files.isEmpty) return null;
    for (final DiffFile file in files) {
      if (file.displayPath == _selectedPath) return file;
    }
    // Nothing chosen yet, or the chosen file is gone from this diff: show
    // the first file rather than an empty pane, since every file here is
    // part of the one thing the user selected on the left.
    return files.first;
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final FileListViewMode viewMode = ref.watch(fileListViewModeProvider);
    final DiffFile? selected = _resolveSelection();

    if (selected == null) {
      return Center(
        child: Text(
          'No changes',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textTertiary,
          ),
        ),
      );
    }

    return GbmSplitPane(
      axis: Axis.vertical,
      spec: GbmLayout.splitterPanelDetailFiles,
      storageId: widget.storageId,
      fixedPaneEnd: GbmFixedPaneEnd.trailing,
      children: <Widget>[
        Container(
          color: colors.surfacePanel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const SizedBox(width: GbmSpacing.space2),
                  Expanded(
                    child: Text(
                      '${widget.diff.files.length} changed '
                      '${widget.diff.files.length == 1 ? 'file' : 'files'}',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  const FileListModeToggleButton(),
                ],
              ),
              Expanded(
                child: FileListModeSwitcher<DiffFile>(
                  mode: viewMode,
                  items: widget.diff.files,
                  pathOf: (DiffFile file) => file.displayPath,
                  leafBuilder: (BuildContext context, DiffFile file) =>
                      _FileRow(
                        file: file,
                        selected: file.displayPath == selected.displayPath,
                        onTap: () =>
                            setState(() => _selectedPath = file.displayPath),
                      ),
                ),
              ),
            ],
          ),
        ),
        DiffPage(
          // Keyed by path so switching files resets DiffPage's own scroll
          // and line-selection State instead of carrying it across.
          key: ValueKey<String>(selected.displayPath),
          diff: ParsedDiff(
            files: <DiffFile>[selected],
            truncated: widget.diff.truncated,
            inputBytes: widget.diff.inputBytes,
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final DiffFile file;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              file.displayPath,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          Text(
            '+${file.addedLines}',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.diffAddText,
            ),
          ),
          const SizedBox(width: GbmSpacing.space1),
          Text(
            '−${file.removedLines}',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.diffDelText,
            ),
          ),
        ],
      ),
    );
  }
}
