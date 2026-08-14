import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/changed_file.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// Container: watches the changed-files providers for [identity] and wires
/// tap callbacks to request the tapped file's diff.
class ChangedFilesPanel extends ConsumerWidget {
  const ChangedFilesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ChangedFile> files = ref.watch(commitFilesProvider(identity));
    final String? selectedPath = ref.watch(
      selectedCommitFilePathProvider(identity),
    );
    final String? selectedCommitOid = ref.watch(
      selectedCommitProvider(identity),
    );

    return ChangedFilesPanelCore(
      hasSelectedCommit: selectedCommitOid != null,
      files: files,
      selectedPath: selectedPath,
      onFileTap: selectedCommitOid == null
          ? null
          : (String path) {
              ref
                      .read(selectedCommitFilePathProvider(identity).notifier)
                      .state =
                  path;
              requestCommitFileDiff(ref, identity, selectedCommitOid, path);
            },
    );
  }
}

/// Presentational: lists [files] for the selected commit, highlighting
/// [selectedPath] and firing [onFileTap] on row tap. No Riverpod dependency,
/// so it's testable directly (mirrors `MenuBarRow`/`TopBar`/`TabRow`'s
/// container/presentational split).
class ChangedFilesPanelCore extends StatelessWidget {
  const ChangedFilesPanelCore({
    super.key,
    required this.hasSelectedCommit,
    required this.files,
    required this.selectedPath,
    required this.onFileTap,
  });

  final bool hasSelectedCommit;
  final List<ChangedFile> files;
  final String? selectedPath;
  final ValueChanged<String>? onFileTap;

  @override
  Widget build(BuildContext context) {
    if (!hasSelectedCommit || files.isEmpty) {
      return Center(
        child: Text(
          'No files changed',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final GbmColors colors = context.gbmColors;

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final ChangedFile file = files[index];
        final bool isSelected = selectedPath == file.path;

        return Container(
          color: isSelected ? colors.surfaceSelected : null,
          child: ListTile(
            dense: true,
            title: Text(
              file.path,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: onFileTap == null ? null : () => onFileTap!(file.path),
          ),
        );
      },
    );
  }
}
