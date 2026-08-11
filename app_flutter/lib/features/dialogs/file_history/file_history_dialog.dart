import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/file_history_entry.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `FileHistoryDialog` (src/app/dialogs/
/// FileHistoryDialog.cpp): the commits that touched one file, newest first.
/// Routed as `/repo/:repoId/dialogs/file-history?path=<path>`.
class FileHistoryDialogContent extends ConsumerStatefulWidget {
  const FileHistoryDialogContent({super.key, required this.identity, this.initialPath = ''});

  final RepoIdentity identity;
  final String initialPath;

  @override
  ConsumerState<FileHistoryDialogContent> createState() => _FileHistoryDialogContentState();
}

class _FileHistoryDialogContentState extends ConsumerState<FileHistoryDialogContent> {
  late final TextEditingController _pathController = TextEditingController(text: widget.initialPath);

  @override
  void initState() {
    super.initState();
    if (widget.initialPath.isNotEmpty) {
      Future.microtask(_load);
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _load() {
    final String path = _pathController.text.trim();
    if (path.isEmpty) return;
    ref.read(repoSessionProvider(widget.identity).notifier).requestFileHistory(path);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<FileHistoryEntry> entries = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.lastFileHistory),
    );

    return GbmDialogShell(
      title: 'File History',
      width: 640,
      actions: <Widget>[GbmButton(label: 'Close', onPressed: () => context.pop())],
      child: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    onSubmitted: (_) => _load(),
                    decoration: const InputDecoration(
                      hintText: 'path/to/file',
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
                  ? Center(child: Text('Enter a path and press Load', style: TextStyle(color: colors.textTertiary)))
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: colors.borderSubtle),
                      itemBuilder: (context, index) => _FileHistoryRow(entry: entries[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileHistoryRow extends StatelessWidget {
  const _FileHistoryRow({required this.entry});

  final FileHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              entry.oid.length > 7 ? entry.oid.substring(0, 7) : entry.oid,
              style: TextStyle(fontFamily: 'monospace', fontSize: GbmTypography.textXs, color: colors.textTertiary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(entry.subject, style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  entry.renamedFrom.isEmpty
                      ? '${entry.status} · ${entry.author.name}'
                      : '${entry.status} (from ${entry.renamedFrom}) · ${entry.author.name}',
                  style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
