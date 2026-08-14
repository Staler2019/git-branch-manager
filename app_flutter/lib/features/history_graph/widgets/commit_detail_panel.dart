import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/commit_meta.dart';
import '../../../data/models/parsed_diff.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../diff/diff_page.dart';

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
  });

  final String? selectedFilePath;
  final bool hasSelectedCommit;
  final CommitMeta? meta;
  final ParsedDiff? diff;

  @override
  Widget build(BuildContext context) {
    if (selectedFilePath == null) {
      return _CommitMetadataView(
        hasSelectedCommit: hasSelectedCommit,
        meta: meta,
      );
    }

    return diff == null
        ? Center(
            child: CircularProgressIndicator(color: context.gbmColors.accent),
          )
        : DiffPage(diff: diff!);
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
