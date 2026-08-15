import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/reflog_entry.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `ReflogDialog` (src/app/dialogs/ReflogDialog.cpp):
/// HEAD's (or another ref's) movement history, newest first. Routed as
/// `/repo/:repoId/dialogs/reflog`.
class ReflogDialogContent extends ConsumerStatefulWidget {
  const ReflogDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ReflogDialogContent> createState() =>
      _ReflogDialogContentState();
}

class _ReflogDialogContentState extends ConsumerState<ReflogDialogContent> {
  final TextEditingController _refController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(repoSessionProvider(widget.identity).notifier)
          .requestReflog(),
    );
  }

  @override
  void dispose() {
    _refController.dispose();
    super.dispose();
  }

  void _load() {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .requestReflog(ref: _refController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<ReflogEntry> entries = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.lastReflog),
    );

    return GbmDialogShell(
      title: 'Reflog',
      width: 680,
      actions: <Widget>[
        GbmButton(label: 'Close', onPressed: () => context.pop()),
      ],
      child: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _refController,
                    onSubmitted: (_) => _load(),
                    decoration: const InputDecoration(
                      hintText: 'HEAD',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                GbmButton(label: 'Load', onPressed: _load),
              ],
            ),
            const SizedBox(height: GbmSpacing.space2),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        'No reflog entries',
                        style: TextStyle(color: colors.textTertiary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: colors.borderSubtle),
                      itemBuilder: (context, index) =>
                          _ReflogRow(entry: entries[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReflogRow extends StatelessWidget {
  const _ReflogRow({required this.entry});

  final ReflogEntry entry;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text(
              '@{${entry.index}}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              entry.oid.length > 7 ? entry.oid.substring(0, 7) : entry.oid,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.message,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.who.name,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
