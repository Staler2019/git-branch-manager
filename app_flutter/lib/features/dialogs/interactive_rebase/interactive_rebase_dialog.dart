import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/rebase_todo_entry.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `InteractiveRebaseDialog` (src/app/dialogs/
/// InteractiveRebaseDialog.cpp). Routed as
/// `/repo/:repoId/dialogs/interactive-rebase`.
class InteractiveRebaseDialogContent extends ConsumerStatefulWidget {
  const InteractiveRebaseDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<InteractiveRebaseDialogContent> createState() => _InteractiveRebaseDialogContentState();
}

class _InteractiveRebaseDialogContentState extends ConsumerState<InteractiveRebaseDialogContent> {
  final TextEditingController _upstreamController = TextEditingController();
  List<RebaseTodoEntry>? _editedTodo;

  @override
  void dispose() {
    _upstreamController.dispose();
    super.dispose();
  }

  void _loadPlan() {
    final String upstream = _upstreamController.text.trim();
    if (upstream.isEmpty) return;
    setState(() => _editedTodo = null);
    ref.read(repoSessionProvider(widget.identity).notifier).requestRebasePlan(upstream);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<RebaseTodoEntry> plan = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.lastRebasePlan),
    );
    final RepoSessionController notifier = ref.read(repoSessionProvider(widget.identity).notifier);
    final List<RebaseTodoEntry> todo = _editedTodo ?? plan;

    return GbmDialogShell(
      title: 'Interactive Rebase',
      width: 720,
      actions: <Widget>[
        GbmButton(label: 'Continue', onPressed: () => notifier.continueRebase()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(label: 'Skip', onPressed: () => notifier.skipRebase()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(label: 'Abort', onPressed: () => notifier.abortRebase()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Start Rebase',
          kind: GbmButtonKind.primary,
          onPressed: todo.isEmpty
              ? null
              : () {
                  final String upstream = _upstreamController.text.trim();
                  notifier.startInteractiveRebase(upstream, todo);
                  context.pop();
                },
        ),
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
                    controller: _upstreamController,
                    onSubmitted: (_) => _loadPlan(),
                    decoration: const InputDecoration(
                      hintText: 'Upstream (e.g. main)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                GbmButton(label: 'Load Plan', onPressed: _loadPlan),
              ],
            ),
            const SizedBox(height: GbmSpacing.space2),
            Expanded(
              child: todo.isEmpty
                  ? Center(child: Text('Enter an upstream and press Load Plan', style: TextStyle(color: colors.textTertiary)))
                  : ListView.builder(
                      itemCount: todo.length,
                      itemBuilder: (context, index) => _TodoRow(
                        entry: todo[index],
                        onActionChanged: (action) {
                          final List<RebaseTodoEntry> updated = List<RebaseTodoEntry>.of(todo);
                          updated[index] = updated[index].copyWith(action: action);
                          setState(() => _editedTodo = updated);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.entry, required this.onActionChanged});

  final RebaseTodoEntry entry;
  final ValueChanged<RebaseTodoAction> onActionChanged;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 110,
            child: DropdownButton<RebaseTodoAction>(
              value: entry.action,
              isDense: true,
              isExpanded: true,
              items: <DropdownMenuItem<RebaseTodoAction>>[
                for (final action in RebaseTodoAction.values)
                  DropdownMenuItem<RebaseTodoAction>(value: action, child: Text(_actionLabel(action))),
              ],
              onChanged: (action) {
                if (action != null) onActionChanged(action);
              },
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          SizedBox(
            width: 64,
            child: Text(
              entry.shortOid.isEmpty ? entry.oid.substring(0, entry.oid.length > 7 ? 7 : entry.oid.length) : entry.shortOid,
              style: TextStyle(fontFamily: 'monospace', fontSize: GbmTypography.textXs, color: colors.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              entry.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: entry.action == RebaseTodoAction.drop ? colors.textTertiary : colors.textPrimary,
                decoration: entry.action == RebaseTodoAction.drop ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _actionLabel(RebaseTodoAction action) => switch (action) {
    RebaseTodoAction.pick => 'Pick',
    RebaseTodoAction.edit => 'Edit',
    RebaseTodoAction.squash => 'Squash',
    RebaseTodoAction.fixup => 'Fixup',
    RebaseTodoAction.drop => 'Drop',
  };
}
