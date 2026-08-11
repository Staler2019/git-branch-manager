import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/bisect_status.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `BisectDialog` (src/app/dialogs/BisectDialog.cpp).
/// Routed as `/repo/:repoId/dialogs/bisect`.
class BisectDialogContent extends ConsumerStatefulWidget {
  const BisectDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<BisectDialogContent> createState() => _BisectDialogContentState();
}

class _BisectDialogContentState extends ConsumerState<BisectDialogContent> {
  final TextEditingController _badRefController = TextEditingController();
  final TextEditingController _goodRefsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(repoSessionProvider(widget.identity).notifier).refreshBisectStatus());
  }

  @override
  void dispose() {
    _badRefController.dispose();
    _goodRefsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BisectStatus status = ref.watch(repoSessionProvider(widget.identity).select((state) => state.bisectStatus));
    final RepoSessionController notifier = ref.read(repoSessionProvider(widget.identity).notifier);

    final Widget body = status.active
        ? _ActiveBisect(status: status, notifier: notifier)
        : _StartBisectForm(
            badRefController: _badRefController,
            goodRefsController: _goodRefsController,
            onStart: () {
              final String badRef = _badRefController.text.trim();
              final List<String> goodRefs = _goodRefsController.text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList();
              notifier.startBisect(badRef: badRef, goodRefs: goodRefs);
            },
          );

    return GbmDialogShell(
      title: 'Bisect',
      width: 560,
      actions: <Widget>[GbmButton(label: 'Close', onPressed: () => context.pop())],
      child: body,
    );
  }
}

class _StartBisectForm extends StatelessWidget {
  const _StartBisectForm({required this.badRefController, required this.goodRefsController, required this.onStart});

  final TextEditingController badRefController;
  final TextEditingController goodRefsController;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Bad commit', style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
        const SizedBox(height: GbmSpacing.space1),
        TextField(
          controller: badRefController,
          decoration: const InputDecoration(hintText: 'HEAD', isDense: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: GbmSpacing.space3),
        Text('Good commit(s), one per line', style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
        const SizedBox(height: GbmSpacing.space1),
        TextField(
          controller: goodRefsController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'v1.0.0', isDense: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: GbmSpacing.space3),
        Align(alignment: Alignment.centerRight, child: GbmButton(label: 'Start Bisect', kind: GbmButtonKind.primary, onPressed: onStart)),
      ],
    );
  }
}

class _ActiveBisect extends StatelessWidget {
  const _ActiveBisect({required this.status, required this.notifier});

  final BisectStatus status;
  final RepoSessionController notifier;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _StatusRow(label: 'Currently testing', value: status.currentOid, colors: colors),
        _StatusRow(label: 'Bad', value: status.badOid, colors: colors),
        _StatusRow(label: 'Good (${status.goodOids.length})', value: status.goodOids.join(', '), colors: colors),
        if (status.skippedOids.isNotEmpty)
          _StatusRow(label: 'Skipped (${status.skippedOids.length})', value: status.skippedOids.join(', '), colors: colors),
        const SizedBox(height: GbmSpacing.space3),
        Row(
          children: <Widget>[
            GbmButton(label: 'Mark Good', kind: GbmButtonKind.primary, onPressed: () => notifier.markBisect(good: true)),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(label: 'Mark Bad', onPressed: () => notifier.markBisect(good: false)),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(label: 'Skip', onPressed: () => notifier.skipBisect()),
            const Spacer(),
            GbmButton(label: 'Reset', onPressed: () => notifier.resetBisect()),
          ],
        ),
        if (status.logText.isNotEmpty) ...<Widget>[
          const SizedBox(height: GbmSpacing.space3),
          Text('Log', style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
          const SizedBox(height: GbmSpacing.space1),
          SizedBox(
            height: 120,
            child: SingleChildScrollView(
              child: SelectableText(
                status.logText,
                style: TextStyle(fontFamily: 'monospace', fontSize: GbmTypography.textXs, color: colors.textTertiary),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, required this.colors});

  final String label;
  final String value;
  final GbmColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary))),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(fontFamily: 'monospace', fontSize: GbmTypography.textSm, color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
