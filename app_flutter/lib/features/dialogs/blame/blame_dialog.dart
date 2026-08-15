import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/blame_result.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `BlameDialog` (src/app/dialogs/BlameDialog.cpp):
/// annotates every line of a file with the commit/author that introduced it.
/// Routed as `/repo/:repoId/dialogs/blame?path=<path>`; `initialPath` (from
/// the `path` query parameter) is pre-filled and loaded automatically when
/// opened from a file row, but can also be typed in directly.
class BlameDialogContent extends ConsumerStatefulWidget {
  const BlameDialogContent({
    super.key,
    required this.identity,
    this.initialPath = '',
  });

  final RepoIdentity identity;
  final String initialPath;

  @override
  ConsumerState<BlameDialogContent> createState() => _BlameDialogContentState();
}

class _BlameDialogContentState extends ConsumerState<BlameDialogContent> {
  late final TextEditingController _pathController = TextEditingController(
    text: widget.initialPath,
  );

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
    ref.read(repoSessionProvider(widget.identity).notifier).requestBlame(path);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final BlameResult? blame = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.lastBlame),
    );

    return GbmDialogShell(
      title: 'Blame',
      width: 760,
      actions: <Widget>[
        GbmButton(label: 'Close', onPressed: () => context.pop()),
      ],
      child: SizedBox(
        height: 440,
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
              child: blame == null
                  ? Center(
                      child: Text(
                        'Enter a path and press Load',
                        style: TextStyle(color: colors.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: blame.lines.length,
                      itemBuilder: (context, index) {
                        final BlameLine line = blame.lines[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: GbmSpacing.space2,
                            vertical: 1,
                          ),
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 70,
                                child: Text(
                                  line.commitOid.length > 7
                                      ? line.commitOid.substring(0, 7)
                                      : line.commitOid,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: GbmTypography.textXs,
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: Text(
                                  line.authorName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: GbmTypography.textXs,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  '${line.finalLine}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: GbmTypography.textXs,
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  line.content,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: GbmTypography.textXs,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (blame?.truncated ?? false)
              Padding(
                padding: const EdgeInsets.only(top: GbmSpacing.space1),
                child: Text(
                  'Result truncated',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
