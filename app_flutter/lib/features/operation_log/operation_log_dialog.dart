import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/operation_record.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `OperationLogView` (src/app/views/
/// OperationLogView.cpp): every `git` invocation this session has made, for
/// support/debugging. Routed as `/repo/:repoId/dialogs/operation-log`.
class OperationLogDialogContent extends ConsumerWidget {
  const OperationLogDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final List<OperationRecord> log = ref.watch(repoSessionProvider(identity).select((state) => state.operationLog));

    return GbmDialogShell(
      title: 'Operation Log',
      width: 720,
      actions: <Widget>[
        GbmButton(
          label: 'Copy All',
          onPressed: log.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: log.map((r) => r.commandLine).join('\n'))),
        ),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Clear',
          onPressed: log.isEmpty ? null : () => ref.read(repoSessionProvider(identity).notifier).clearOperationLog(),
        ),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(label: 'Close', kind: GbmButtonKind.primary, onPressed: () => context.pop()),
      ],
      child: SizedBox(
        height: 420,
        child: log.isEmpty
            ? Center(child: Text('No operations recorded yet', style: TextStyle(color: colors.textTertiary)))
            : ListView.builder(
                reverse: true,
                itemCount: log.length,
                itemBuilder: (context, index) => _OperationRow(record: log[log.length - 1 - index]),
              ),
      ),
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({required this.record});

  final OperationRecord record;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Color statusColor = record.failed ? colors.danger : colors.textTertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  record.commandLine,
                  style: TextStyle(fontSize: GbmTypography.textSm, fontFamily: 'monospace', color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              Text(
                '${record.durationMs}ms',
                style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary),
              ),
              if (record.failed) ...<Widget>[
                const SizedBox(width: GbmSpacing.space1),
                Text('exit ${record.exitCode}', style: TextStyle(fontSize: GbmTypography.textXs, color: statusColor)),
              ],
            ],
          ),
          if (record.failed && record.stderrText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: GbmSpacing.space1),
              child: SelectableText(
                record.stderrText,
                style: TextStyle(fontSize: GbmTypography.textXs, fontFamily: 'monospace', color: colors.diffDelText),
              ),
            ),
        ],
      ),
    );
  }
}
