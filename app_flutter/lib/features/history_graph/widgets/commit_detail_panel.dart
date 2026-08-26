import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/commit_meta.dart';
import '../../../data/models/parsed_diff.dart';
import '../../../data/repositories/diff_view_mode_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_segmented_control.dart';
import '../../diff/diff_page.dart';
import '../../diff/side_by_side_diff_view.dart';

/// Container: watches the selected commit/file providers for [identity] and
/// resolves the metadata or diff to show.
class CommitDetailPanel extends ConsumerWidget {
  const CommitDetailPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? selectedFilePath = ref.watch(
      selectedCommitFilePathProvider(identity),
    );
    final String? selectedCommitOid = ref.watch(
      selectedCommitProvider(identity),
    );
    final CommitMeta? meta = selectedCommitOid == null
        ? null
        : ref.watch(commitMetaProvider(identity))[selectedCommitOid];
    final ParsedDiff? diff = selectedFilePath == null
        ? null
        : ref.watch(commitFileDiffProvider(identity));

    return CommitDetailPanelCore(
      selectedFilePath: selectedFilePath,
      hasSelectedCommit: selectedCommitOid != null,
      meta: meta,
      diff: diff,
      diffViewMode: ref.watch(diffViewModeProvider),
      onDiffViewModeChanged: (DiffViewMode mode) =>
          ref.read(diffViewModeProvider.notifier).setMode(mode),
    );
  }
}

/// Presentational: mutually exclusive between commit metadata and a file's
/// diff, driven entirely by constructor params. No Riverpod dependency, so
/// it's testable directly (mirrors `MenuBarRow`/`TopBar`/`TabRow`'s
/// container/presentational split).
///
/// [selectedFilePath] == null selects the metadata view; non-null selects
/// the diff view. [hasSelectedCommit] and [meta] are independent because a
/// commit can be selected while its metadata is still loading.
class CommitDetailPanelCore extends StatelessWidget {
  const CommitDetailPanelCore({
    super.key,
    required this.selectedFilePath,
    required this.hasSelectedCommit,
    required this.meta,
    required this.diff,
    required this.diffViewMode,
    required this.onDiffViewModeChanged,
  });

  final String? selectedFilePath;
  final bool hasSelectedCommit;
  final CommitMeta? meta;
  final ParsedDiff? diff;

  /// Which layout the diff face uses. A param rather than a `ref.watch` in
  /// here, so this half stays Riverpod-free and directly pumpable -- the
  /// same split MenuBarRow and TabRow keep.
  final DiffViewMode diffViewMode;

  /// Reports the key the user pressed. The persisting is [CommitDetailPanel]'s
  /// job; this widget holds no state of its own.
  final ValueChanged<DiffViewMode> onDiffViewModeChanged;

  @override
  Widget build(BuildContext context) {
    if (selectedFilePath == null) {
      return _CommitMetadataView(
        hasSelectedCommit: hasSelectedCommit,
        meta: meta,
      );
    }

    final ParsedDiff? diff = this.diff;
    if (diff == null) {
      // No titlebar with the spinner: its switch would have nothing to lay
      // out either way, and a control that does nothing when pressed reads
      // as broken rather than as pending.
      return Center(
        child: CircularProgressIndicator(color: context.gbmColors.accent),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DiffTitleBar(
          displayPath: selectedFilePath!,
          mode: diffViewMode,
          onModeChanged: onDiffViewModeChanged,
        ),
        Expanded(
          child: switch (diffViewMode) {
            DiffViewMode.unified => DiffPage(diff: diff),
            DiffViewMode.sideBySide => SideBySideDiffView(diff: diff),
          },
        ),
      ],
    );
  }
}

/// Names the file being diffed and carries the 並排 / unified switch.
///
/// Deliberately the same shape as the Working Copy's own diff titlebar
/// (`working_copy_diff_pane.dart`'s `_TitleBar`) -- same height, same
/// raised surface, same bottom border, path elided on the left and the
/// switch pinned right -- because they are the same furniture doing the same
/// job in two views. What they are *not* is the same switch: that one picks
/// between unstaged and staged, this one between 變更前 and 變更後.
///
/// This is also the only entry point to the mode, with no menu item and no
/// shortcut. That matches the Working Copy's switch exactly, and is a
/// deliberate alignment rather than an omission.
class _DiffTitleBar extends StatelessWidget {
  const _DiffTitleBar({
    required this.displayPath,
    required this.mode,
    required this.onModeChanged,
  });

  final String displayPath;
  final DiffViewMode mode;
  final ValueChanged<DiffViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfacePanelRaised,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: <Widget>[
          // Flexible, not Expanded: RenderFlex lays non-flex children out
          // first, so a path insisting on its full width would push the
          // switch off the end of the bar instead of eliding itself.
          Flexible(
            child: Text(
              displayPath,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          const SizedBox(width: GbmSpacing.space2),
          GbmSegmentedControl<DiffViewMode>(
            value: mode,
            onChanged: onModeChanged,
            options: const <GbmSegmentedOption<DiffViewMode>>[
              GbmSegmentedOption<DiffViewMode>(
                value: DiffViewMode.sideBySide,
                label: 'side by side',
                icon: Icons.vertical_split,
                showLabel: true,
              ),
              GbmSegmentedOption<DiffViewMode>(
                value: DiffViewMode.unified,
                label: 'unified',
                icon: Icons.view_stream,
                showLabel: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows commit metadata: subject, full body, and other metadata.
class _CommitMetadataView extends StatelessWidget {
  const _CommitMetadataView({
    required this.hasSelectedCommit,
    required this.meta,
  });

  final bool hasSelectedCommit;
  final CommitMeta? meta;

  @override
  Widget build(BuildContext context) {
    if (!hasSelectedCommit) {
      return Center(
        child: Text(
          'Select a commit to view details',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final CommitMeta? meta = this.meta;
    if (meta == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final GbmColors colors = context.gbmColors;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meta.subject,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (meta.body.isNotEmpty) ...[
              Text(
                meta.body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Divider(color: colors.borderSubtle),
            const SizedBox(height: 8),
            Text(
              'Author: ${meta.author.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
