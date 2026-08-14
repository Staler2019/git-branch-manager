import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/stash_entry.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../diff/diff_page.dart';

/// The Dart analog of `ManageStashesDialog` (src/app/dialogs/
/// ManageStashesDialog.cpp). Routed as `/repo/:repoId/dialogs/manage-stashes`.
class ManageStashesDialogContent extends ConsumerStatefulWidget {
  const ManageStashesDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ManageStashesDialogContent> createState() =>
      _ManageStashesDialogContentState();
}

class _ManageStashesDialogContentState
    extends ConsumerState<ManageStashesDialogContent> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(repoSessionProvider(widget.identity).notifier)
          .refreshStashes(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<StashEntry> stashes = session.stashes;
    final StashDiffReply? diff = session.lastStashDiff;

    return GbmDialogShell(
      title: 'Manage Stashes',
      width: 720,
      actions: <Widget>[
        GbmButton(label: 'Close', onPressed: () => context.pop()),
      ],
      child: SizedBox(
        height: 360,
        child: stashes.isEmpty
            ? Center(
                child: Text(
                  'No stashes',
                  style: TextStyle(color: colors.textTertiary),
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 280,
                    child: ListView(
                      children: <Widget>[
                        for (final entry in stashes)
                          _StashRow(
                            entry: entry,
                            selected: entry.index == _selectedIndex,
                            onTap: () {
                              setState(() => _selectedIndex = entry.index);
                              ref
                                  .read(
                                    repoSessionProvider(
                                      widget.identity,
                                    ).notifier,
                                  )
                                  .requestStashDiff(entry.index);
                            },
                            onApply: () => ref
                                .read(
                                  repoSessionProvider(widget.identity).notifier,
                                )
                                .applyStash(entry.index),
                            onPop: () => ref
                                .read(
                                  repoSessionProvider(widget.identity).notifier,
                                )
                                .applyStash(entry.index, pop: true),
                            onDrop: () => ref
                                .read(
                                  repoSessionProvider(widget.identity).notifier,
                                )
                                .dropStash(entry.index),
                          ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: colors.borderSubtle),
                  Expanded(
                    child: _selectedIndex == null
                        ? Center(
                            child: Text(
                              'Select a stash',
                              style: TextStyle(color: colors.textTertiary),
                            ),
                          )
                        : (diff != null && diff.index == _selectedIndex)
                        ? DiffPage(diff: diff.diff)
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StashRow extends StatelessWidget {
  const _StashRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onApply,
    required this.onPop,
    required this.onDrop,
  });

  final StashEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onApply;
  final VoidCallback onPop;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Material(
      color: selected ? colors.surfaceSelected : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space3,
            vertical: GbmSpacing.space2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'stash@{${entry.index}}: ${entry.message}',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                  fontWeight: GbmTypography.weightMedium,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: GbmSpacing.space1),
              Wrap(
                spacing: GbmSpacing.space1,
                children: <Widget>[
                  _MiniButton(label: 'Apply', onPressed: onApply),
                  _MiniButton(label: 'Pop', onPressed: onPop),
                  _MiniButton(label: 'Drop', onPressed: onDrop),
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
      child: Text(
        label,
        style: const TextStyle(fontSize: GbmTypography.textXs),
      ),
    );
  }
}
