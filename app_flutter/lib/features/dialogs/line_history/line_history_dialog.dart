import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/line_history_chunk.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `LineHistoryDialog` (src/app/dialogs/
/// LineHistoryDialog.cpp): the commits that touched a specific line range of
/// a file (`git log -L`). Routed as `/repo/:repoId/dialogs/line-history`
/// with optional `path`/`startLine`/`endLine` query parameters.
class LineHistoryDialogContent extends ConsumerStatefulWidget {
  const LineHistoryDialogContent({
    super.key,
    required this.identity,
    this.initialPath = '',
    this.initialStartLine = 1,
    this.initialEndLine = 1,
  });

  final RepoIdentity identity;
  final String initialPath;
  final int initialStartLine;
  final int initialEndLine;

  @override
  ConsumerState<LineHistoryDialogContent> createState() =>
      _LineHistoryDialogContentState();
}

class _LineHistoryDialogContentState
    extends ConsumerState<LineHistoryDialogContent> {
  late final TextEditingController _pathController = TextEditingController(
    text: widget.initialPath,
  );
  late final TextEditingController _startController = TextEditingController(
    text: '${widget.initialStartLine}',
  );
  late final TextEditingController _endController = TextEditingController(
    text: '${widget.initialEndLine}',
  );
  int? _selectedIndex;

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
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _load() {
    final String path = _pathController.text.trim();
    final int? startLine = int.tryParse(_startController.text.trim());
    final int? endLine = int.tryParse(_endController.text.trim());
    if (path.isEmpty || startLine == null || endLine == null) return;
    setState(() => _selectedIndex = null);
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .requestLineHistory(path, startLine, endLine);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<LineHistoryChunk> chunks = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((state) => state.lastLineHistory),
    );

    return GbmDialogShell(
      title: 'Line History',
      width: 760,
      actions: <Widget>[
        GbmButton(label: 'Close', onPressed: () => context.pop()),
      ],
      child: SizedBox(
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      hintText: 'path/to/file',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                Expanded(
                  child: TextField(
                    controller: _startController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Start',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                Expanded(
                  child: TextField(
                    controller: _endController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'End',
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
              child: chunks.isEmpty
                  ? Center(
                      child: Text(
                        'Enter a path and line range, then press Load',
                        style: TextStyle(color: colors.textTertiary),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: 260,
                          child: ListView.builder(
                            itemCount: chunks.length,
                            itemBuilder: (context, index) {
                              final LineHistoryChunk chunk = chunks[index];
                              return _LineHistoryRow(
                                chunk: chunk,
                                selected: index == _selectedIndex,
                                onTap: () =>
                                    setState(() => _selectedIndex = index),
                              );
                            },
                          ),
                        ),
                        VerticalDivider(width: 1, color: colors.borderSubtle),
                        Expanded(
                          child: _selectedIndex == null
                              ? Center(
                                  child: Text(
                                    'Select a commit',
                                    style: TextStyle(
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                )
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.all(
                                    GbmSpacing.space2,
                                  ),
                                  child: SelectableText(
                                    chunks[_selectedIndex!].diffText,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: GbmTypography.textXs,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineHistoryRow extends StatelessWidget {
  const _LineHistoryRow({
    required this.chunk,
    required this.selected,
    required this.onTap,
  });

  final LineHistoryChunk chunk;
  final bool selected;
  final VoidCallback onTap;

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
                chunk.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${chunk.oid.length > 7 ? chunk.oid.substring(0, 7) : chunk.oid} · ${chunk.author.name}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
