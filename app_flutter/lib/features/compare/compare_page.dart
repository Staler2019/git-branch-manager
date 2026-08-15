import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/parsed_diff.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/models/stash_entry.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_badge.dart';
import '../diff/diff_page.dart';
import 'widgets/compare_ref_picker.dart';

/// Builds the full mixed branch/tag/stash/working-copy option list a
/// [CompareRefPicker] shows -- shared by both sides (spec page 12: "混一份
/// ref picker"), except the left side excludes Working Copy: gbm_capi only
/// supports a ref as the "before" side of a working-tree diff
/// (DiffService::commitVsWorkingTree takes one commit, always compared
/// against the live tree as "after" -- there is no reverse direction), so
/// offering Working Copy on the left would silently have nowhere to go.
List<CompareRefOption> compareRefOptions(
  RefSnapshot refs,
  List<StashEntry> stashes, {
  required bool includeWorkingCopy,
}) {
  return <CompareRefOption>[
    if (includeWorkingCopy)
      const CompareRefOption(
        kind: CompareRefOptionKind.workingCopy,
        label: 'Working Copy',
      ),
    for (final RefInfo ref in refs.localBranches)
      CompareRefOption(
        kind: CompareRefOptionKind.branch,
        label: ref.shortName,
        value: ref.shortName,
      ),
    for (final RefInfo ref in refs.remoteBranches)
      CompareRefOption(
        kind: CompareRefOptionKind.branch,
        label: ref.shortName,
        value: ref.shortName,
      ),
    for (final RefInfo ref in refs.tags)
      CompareRefOption(
        kind: CompareRefOptionKind.tag,
        label: ref.shortName,
        value: ref.shortName,
      ),
    for (final StashEntry stash in stashes)
      CompareRefOption(
        kind: CompareRefOptionKind.stash,
        label: 'stash@{${stash.index}}: ${stash.message}',
        value: 'stash@{${stash.index}}',
      ),
  ];
}

/// The Compare tab (spec page 12): two-ref or ref-vs-working-copy diff,
/// routed as `/repo/:repoId/compare/:tabId` -- a ShellRoute child like
/// History/Working Copy (not a standalone window, unlike the conflict
/// resolution route), since it's one of several tabs in the normal
/// workspace tab strip. `tabId` selects which open [CompareTabSpec]
/// (compare_tabs_repository.dart) to render.
class ComparePage extends ConsumerStatefulWidget {
  const ComparePage({super.key, required this.identity, required this.tabId});

  final RepoIdentity identity;
  final String tabId;

  @override
  ConsumerState<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends ConsumerState<ComparePage> {
  String? _selectedPath;
  late final ScrollController _fileListController;
  (String, String?, bool)? _lastRequested;

  @override
  void initState() {
    super.initState();
    final List<CompareTabSpec> tabs = ref.read(
      compareTabsProvider(widget.identity),
    );
    final CompareTabSpec? spec = _findSpec(tabs);
    _fileListController = ScrollController(
      initialScrollOffset: spec?.scrollOffset ?? 0,
    );
    if (spec != null) {
      Future.microtask(() => _request(spec));
    }
  }

  @override
  void dispose() {
    _fileListController.dispose();
    super.dispose();
  }

  CompareTabSpec? _findSpec(List<CompareTabSpec> tabs) {
    for (final CompareTabSpec tab in tabs) {
      if (tab.id == widget.tabId) return tab;
    }
    return null;
  }

  void _request(CompareTabSpec spec) {
    final (String, String?, bool) key = (spec.left, spec.right, spec.threeDot);
    if (_lastRequested == key) return;
    _lastRequested = key;
    final RepoSessionController controller = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );
    if (spec.rightIsWorkingCopy) {
      controller.requestCompareWithWorkingCopy(spec.left);
    } else {
      controller.requestCompareRefs(
        spec.left,
        spec.right!,
        threeDot: spec.threeDot,
      );
    }
  }

  void _onScrollEnd() {
    ref
        .read(compareTabsProvider(widget.identity).notifier)
        .updateScrollOffset(widget.tabId, _fileListController.offset);
  }

  void _closeThisTab(BuildContext context) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    context.go(RoutePaths.historyFor(repoId));
    ref.read(compareTabsProvider(widget.identity).notifier).close(widget.tabId);
  }

  Future<void> _confirmCheckout(
    BuildContext context, {
    required String path,
    required String source,
  }) async {
    final GbmColors colors = context.gbmColors;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Overwrite working copy?'),
        content: Text(
          'This replaces the uncommitted contents of "$path" with its '
          'version at "$source". This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Checkout', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      ref
          .read(repoSessionProvider(widget.identity).notifier)
          .restorePaths(<String>[path], source: source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<CompareTabSpec> tabs = ref.watch(
      compareTabsProvider(widget.identity),
    );
    final CompareTabSpec? spec = _findSpec(tabs);

    ref.listen<List<CompareTabSpec>>(compareTabsProvider(widget.identity), (
      previous,
      next,
    ) {
      final CompareTabSpec? nextSpec = _findSpec(next);
      if (nextSpec != null) _request(nextSpec);
    });

    if (spec == null) {
      // Closed mid-navigation (e.g. Ctrl/Cmd+W raced a route change) --
      // nothing to render; the caller is already navigating away.
      return const SizedBox.shrink();
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
            _closeThisTab(context),
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
            _closeThisTab(context),
      },
      child: Focus(autofocus: true, child: _buildBody(context, spec)),
    );
  }

  Widget _buildBody(BuildContext context, CompareTabSpec spec) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<CompareRefOption> leftOptions = compareRefOptions(
      session.refs,
      session.stashes,
      includeWorkingCopy: false,
    );
    final List<CompareRefOption> rightOptions = compareRefOptions(
      session.refs,
      session.stashes,
      includeWorkingCopy: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(GbmSpacing.space3),
          child: Row(
            children: <Widget>[
              Expanded(
                child: CompareRefPicker(
                  options: leftOptions,
                  value: spec.left,
                  onChanged: (String? left) => _updateRefs(
                    spec,
                    left: left ?? spec.left,
                    right: spec.right,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Swap',
                icon: Icon(Icons.swap_horiz, color: colors.textSecondary),
                onPressed: spec.rightIsWorkingCopy
                    ? null
                    : () => _updateRefs(
                        spec,
                        left: spec.right!,
                        right: spec.left,
                      ),
              ),
              Expanded(
                child: CompareRefPicker(
                  options: rightOptions,
                  value: spec.right,
                  onChanged: (String? right) =>
                      _updateRefs(spec, left: spec.left, right: right),
                ),
              ),
              if (!spec.rightIsWorkingCopy) ...<Widget>[
                const SizedBox(width: GbmSpacing.space2),
                _ThreeDotToggle(
                  threeDot: spec.threeDot,
                  onChanged: (bool value) => ref
                      .read(compareTabsProvider(widget.identity).notifier)
                      .updateRefs(
                        spec.id,
                        left: spec.left,
                        right: spec.right,
                        threeDot: value,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (!spec.rightIsWorkingCopy) _buildMergeBaseLine(context, spec),
        const Divider(height: 1),
        Expanded(child: _buildResult(context, spec, session)),
      ],
    );
  }

  void _updateRefs(CompareTabSpec spec, {required String left, String? right}) {
    ref
        .read(compareTabsProvider(widget.identity).notifier)
        .updateRefs(
          spec.id,
          left: left,
          right: right,
          threeDot: spec.threeDot,
        );
  }

  Widget _buildMergeBaseLine(BuildContext context, CompareTabSpec spec) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final CompareResult? result =
        session.compareResults[CompareResult.key(
          spec.left,
          spec.right!,
          spec.threeDot,
        )];
    final String text = result == null
        ? 'Comparing…'
        : result.mergeBase.isEmpty
        ? 'No common ancestor (unrelated histories)'
        : 'Merge base: ${result.mergeBase.substring(0, result.mergeBase.length < 8 ? result.mergeBase.length : 8)}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space1,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary),
      ),
    );
  }

  Widget _buildResult(
    BuildContext context,
    CompareTabSpec spec,
    RepoSessionState session,
  ) {
    if (spec.rightIsWorkingCopy) {
      final CompareWithWorkingCopyResult? result =
          session.compareWithWorkingCopyResults[CompareWithWorkingCopyResult.key(
            spec.left,
          )];
      if (result == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 260,
            child: _WorkingCopyFileList(
              controller: _fileListController,
              onScrollEnd: _onScrollEnd,
              files: result.diff.files,
              selectedPath: _selectedPath,
              onSelect: (String path) => setState(() => _selectedPath = path),
              onCheckout: (String path) => _confirmCheckout(
                context,
                path: path,
                source: spec.left,
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildDiffView(result.diff)),
        ],
      );
    }

    final CompareResult? result =
        session.compareResults[CompareResult.key(
          spec.left,
          spec.right!,
          spec.threeDot,
        )];
    if (result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 260,
          child: _RefCompareFileList(
            controller: _fileListController,
            onScrollEnd: _onScrollEnd,
            files: result.files,
            selectedPath: _selectedPath,
            onSelect: (String path) {
              setState(() => _selectedPath = path);
              ref
                  .read(repoSessionProvider(widget.identity).notifier)
                  .requestCompareFileDiff(
                    spec.left,
                    spec.right!,
                    path,
                    threeDot: spec.threeDot,
                  );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedPath == null
              ? Center(
                  child: Text(
                    'Select a file to view its diff',
                    style: TextStyle(color: context.gbmColors.textTertiary),
                  ),
                )
              : _buildSelectedFileDiff(session, spec),
        ),
      ],
    );
  }

  Widget _buildSelectedFileDiff(RepoSessionState session, CompareTabSpec spec) {
    final CompareFileDiffResult? diffResult =
        session.compareFileDiffResults[CompareFileDiffResult.key(
          spec.left,
          spec.right!,
          spec.threeDot,
          _selectedPath!,
        )];
    if (diffResult == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildDiffView(diffResult.diff);
  }

  Widget _buildDiffView(ParsedDiff diff) {
    if (_selectedPath == null) {
      return DiffPage(diff: diff);
    }
    final List<DiffFile> filtered = diff.files
        .where((DiffFile f) => f.displayPath == _selectedPath)
        .toList(growable: false);
    return DiffPage(
      diff: ParsedDiff(
        files: filtered,
        truncated: diff.truncated,
        inputBytes: diff.inputBytes,
      ),
    );
  }
}

class _ThreeDotToggle extends StatelessWidget {
  const _ThreeDotToggle({required this.threeDot, required this.onChanged});

  final bool threeDot;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(value: true, label: Text('...')),
        ButtonSegment<bool>(value: false, label: Text('..')),
      ],
      selected: <bool>{threeDot},
      onSelectionChanged: (Set<bool> selection) => onChanged(selection.first),
    );
  }
}

/// Read-only changed-file list for the ref-vs-ref side (spec: "結果唯讀") --
/// no checkout action, unlike [_WorkingCopyFileList], since neither side is
/// the live working tree.
class _RefCompareFileList extends StatelessWidget {
  const _RefCompareFileList({
    required this.controller,
    required this.onScrollEnd,
    required this.files,
    required this.selectedPath,
    required this.onSelect,
  });

  final ScrollController controller;
  final VoidCallback onScrollEnd;
  final List<DiffFile> files;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    if (files.isEmpty) {
      return Center(
        child: Text('No changes', style: TextStyle(color: colors.textTertiary)),
      );
    }
    return NotificationListener<ScrollEndNotification>(
      onNotification: (ScrollEndNotification notification) {
        onScrollEnd();
        return false;
      },
      child: ListView.builder(
        controller: controller,
        itemCount: files.length,
        itemBuilder: (context, index) {
          final DiffFile file = files[index];
          final bool isSelected = file.displayPath == selectedPath;
          return Container(
            color: isSelected ? colors.surfaceSelected : null,
            child: ListTile(
              dense: true,
              title: Text(
                file.displayPath,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (file.addedLines > 0)
                    GbmBadge(
                      label: '+${file.addedLines}',
                      kind: GbmBadgeKind.added,
                    ),
                  if (file.removedLines > 0) ...<Widget>[
                    const SizedBox(width: GbmSpacing.space1),
                    GbmBadge(
                      label: '-${file.removedLines}',
                      kind: GbmBadgeKind.removed,
                    ),
                  ],
                ],
              ),
              onTap: () => onSelect(file.displayPath),
            ),
          );
        },
      ),
    );
  }
}

/// Changed-file list for the ref-vs-Working-Copy side, with a per-file
/// checkout (overwrite) action -- spec: "與 working copy 比較時逐檔
/// checkout 覆蓋（動作前必有確認 dialog）". [onCheckout] itself only opens
/// the confirmation; the destructive call happens after the user confirms
/// (see _ComparePageState._confirmCheckout).
class _WorkingCopyFileList extends StatelessWidget {
  const _WorkingCopyFileList({
    required this.controller,
    required this.onScrollEnd,
    required this.files,
    required this.selectedPath,
    required this.onSelect,
    required this.onCheckout,
  });

  final ScrollController controller;
  final VoidCallback onScrollEnd;
  final List<DiffFile> files;
  final String? selectedPath;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCheckout;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    if (files.isEmpty) {
      return Center(
        child: Text('No changes', style: TextStyle(color: colors.textTertiary)),
      );
    }
    return NotificationListener<ScrollEndNotification>(
      onNotification: (ScrollEndNotification notification) {
        onScrollEnd();
        return false;
      },
      child: ListView.builder(
        controller: controller,
        itemCount: files.length,
        itemBuilder: (context, index) {
          final DiffFile file = files[index];
          final bool isSelected = file.displayPath == selectedPath;
          return Container(
            color: isSelected ? colors.surfaceSelected : null,
            child: ListTile(
              dense: true,
              title: Text(
                file.displayPath,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Checkout (overwrite working copy)',
                icon: Icon(
                  Icons.settings_backup_restore,
                  size: 16,
                  color: colors.textSecondary,
                ),
                onPressed: () => onCheckout(file.displayPath),
              ),
              onTap: () => onSelect(file.displayPath),
            ),
          );
        },
      ),
    );
  }
}
