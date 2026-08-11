import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/repo_state.dart';
import '../../data/models/working_copy_status.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/repositories/working_copy_repository.dart' as wc;
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../diff/diff_page.dart';

/// The Dart analog of `ConflictResolveWindow` (src/app/views/
/// ConflictResolveWindow.cpp). Routed as `/repo/:repoId/conflicts` -- a
/// standalone top-level route (not a dialog overlay), matching the Qt
/// version's own restartable, independent window: a conflict resolution can
/// span an app restart, so it needs to be reachable directly rather than
/// living only as ephemeral dialog state.
class ConflictResolveWindow extends ConsumerStatefulWidget {
  const ConflictResolveWindow({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ConflictResolveWindow> createState() => _ConflictResolveWindowState();
}

class _ConflictResolveWindowState extends ConsumerState<ConflictResolveWindow> {
  String? _selectedPath;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(repoSessionProvider(widget.identity));
    final String repoId = Uri.encodeComponent(widget.identity.workDir);

    if (!session.isOpen) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.go(RoutePaths.repoList))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final List<WorkingCopyEntry> conflicted = session.workingCopyStatus.conflicted;
    final Object? diff = ref.watch(wc.repoLastDiffProvider(widget.identity));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(RoutePaths.workingCopyFor(repoId))),
        title: const Text('Resolve Conflicts'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (session.repoState case final state? when state.isMerging || state.isCherryPicking || state.isReverting)
            _SequencerBanner(identity: widget.identity, state: state),
          if (session.lastError case final error?)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(GbmSpacing.space2),
              color: colors.diffDelBg,
              child: Text(error.message, style: TextStyle(color: colors.diffDelText, fontSize: GbmTypography.textSm)),
            ),
          Expanded(
            child: conflicted.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('No conflicts remaining.', style: TextStyle(color: colors.textSecondary)),
                        const SizedBox(height: GbmSpacing.space3),
                        GbmButton(
                          label: 'Go to Working Copy',
                          kind: GbmButtonKind.primary,
                          onPressed: () => context.go(RoutePaths.workingCopyFor(repoId)),
                        ),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 320,
                        child: ListView(
                          children: <Widget>[
                            for (final entry in conflicted)
                              _ConflictRow(
                                entry: entry,
                                selected: entry.path == _selectedPath,
                                onTap: () {
                                  setState(() => _selectedPath = entry.path);
                                  wc.requestWorkingCopyDiff(ref, widget.identity, entry.path);
                                },
                                onTakeOurs: () => wc.resolveConflict(
                                  ref,
                                  widget.identity,
                                  entry.path,
                                  ConflictResolution.takeOurs,
                                  oursBlobMissing: entry.oursBlob.isEmpty,
                                ),
                                onTakeTheirs: () => wc.resolveConflict(
                                  ref,
                                  widget.identity,
                                  entry.path,
                                  ConflictResolution.takeTheirs,
                                  theirsBlobMissing: entry.theirsBlob.isEmpty,
                                ),
                                onMarkResolved: () =>
                                    wc.resolveConflict(ref, widget.identity, entry.path, ConflictResolution.markResolved),
                              ),
                          ],
                        ),
                      ),
                      VerticalDivider(width: 1, color: colors.borderSubtle),
                      Expanded(
                        child: _selectedPath == null
                            ? Center(child: Text('Select a file', style: TextStyle(color: colors.textTertiary)))
                            : (diff is WorkingCopyDiffReply && diff.path == _selectedPath)
                            ? DiffPage(diff: diff.diff)
                            : const Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SequencerBanner extends ConsumerWidget {
  const _SequencerBanner({required this.identity, required this.state});

  final RepoIdentity identity;
  final RepoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final String label = state.isMerging
        ? 'Merge in progress'
        : state.isCherryPicking
        ? 'Cherry-pick in progress'
        : 'Revert in progress';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3, vertical: GbmSpacing.space2),
      color: colors.surfacePanelRaised,
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textPrimary))),
          if (state.isMerging)
            GbmButton(label: 'Abort Merge', onPressed: () => ref.read(repoSessionProvider(identity).notifier).mergeAbort()),
        ],
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onTakeOurs,
    required this.onTakeTheirs,
    required this.onMarkResolved,
  });

  final WorkingCopyEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTakeOurs;
  final VoidCallback onTakeTheirs;
  final VoidCallback onMarkResolved;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Material(
      color: selected ? colors.surfaceSelected : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3, vertical: GbmSpacing.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.path,
                style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textPrimary, fontWeight: GbmTypography.weightMedium),
              ),
              const SizedBox(height: GbmSpacing.space1),
              Wrap(
                spacing: GbmSpacing.space1,
                children: <Widget>[
                  _MiniButton(label: 'Take Ours', onPressed: onTakeOurs),
                  _MiniButton(label: 'Take Theirs', onPressed: onTakeTheirs),
                  _MiniButton(label: 'Mark Resolved', onPressed: onMarkResolved),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        minimumSize: const Size(0, 24),
        foregroundColor: colors.textSecondary,
      ),
      child: Text(label, style: const TextStyle(fontSize: GbmTypography.textXs)),
    );
  }
}
