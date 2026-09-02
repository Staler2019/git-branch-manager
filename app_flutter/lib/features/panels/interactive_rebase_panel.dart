import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/rebase_todo_entry.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_row.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_widgets.dart';

/// `interactive-rebase` as a tab (spec page 14 `IAMAP`), on page 19's
/// template. Reached from Tools → Rewrite history ▸ Interactive rebase… —
/// P14 rule 2 keeps the destructive/multi-step three off the top level.
///
/// P19 `PANELSPEC` row:
/// - list: commit 序列（可拖曳排序）
/// - detail: 每筆的動作（pick / squash / drop）與訊息編輯
/// - toolbar: Start、Abort、Reset order
///
/// **Which segment each action lands in (P19 rule 2).** `Start` is the only
/// action that begins anything, so it is primary. `Abort` and `Reset order`
/// both put something back the way it was — maintenance. Nothing here opens
/// an external tool, so there is no 「跳出去」 segment and no separator.
///
/// **Nothing moves to the detail action row.** `Abort` is the closest
/// candidate and stays: rule 2 keeps 破壞性動作 off the toolbar, and aborting
/// a rebase *restores the prior state* rather than destroying work. It is
/// also this panel's only escape hatch, and the detail action row is only
/// drawn once something is selected — putting the exit behind a selection is
/// worse than leaving it where it is.
///
/// **訊息編輯 is absent, by an existing design decision rather than a gap.**
/// `RebaseTodoEntry.subject` is the todo line's comment, not an editable
/// message, and `Reword` is deliberately not one of the actions: with no
/// terminal or editor available, a reword step would run to completion
/// silently keeping the original message — indistinguishable from Pick (see
/// `src/core/git/ops/RebaseOps.h`). `Edit` is the verb that works: the
/// rebase stops with the commit checked out and the existing amend flow
/// changes the message before Continue. Offering a message box here would
/// promise something the plan cannot carry.
///
/// **The plan is edited locally before anything runs.** `requestRebasePlan`
/// is read-only — it builds the todo list `git rebase -i` would have opened
/// an editor on — so reordering and action changes live in this widget's
/// state until Start submits them. That is why `Reset order` exists: it
/// throws the local edits away and re-seeds from the published plan.
class InteractiveRebasePanel extends ConsumerStatefulWidget {
  const InteractiveRebasePanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<InteractiveRebasePanel> createState() =>
      _InteractiveRebasePanelState();
}

class _InteractiveRebasePanelState
    extends ConsumerState<InteractiveRebasePanel> {
  final TextEditingController _upstreamController = TextEditingController();

  /// The locally-edited plan. Null until a plan has been loaded, which is
  /// what tells [_seedFrom] a freshly-published plan is new rather than the
  /// same one arriving again.
  List<RebaseTodoEntry>? _todo;
  List<RebaseTodoEntry> _publishedPlan = const <RebaseTodoEntry>[];
  String? _selectedOid;

  @override
  void dispose() {
    _upstreamController.dispose();
    super.dispose();
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  /// Adopts a newly-published plan, discarding local edits — a new plan is a
  /// different rebase, so keeping edits from the previous one would silently
  /// apply them to the wrong commits.
  void _seedFrom(List<RebaseTodoEntry> plan) {
    if (identical(plan, _publishedPlan)) return;
    _publishedPlan = plan;
    _todo = List<RebaseTodoEntry>.of(plan);
    _selectedOid = null;
  }

  void _setAction(String oid, RebaseTodoAction action) {
    setState(() {
      _todo = <RebaseTodoEntry>[
        for (final RebaseTodoEntry e in _todo ?? const <RebaseTodoEntry>[])
          e.oid == oid ? e.copyWith(action: action) : e,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    // Seeding during build is safe because it only ever runs on a plan the
    // controller has just published, and it touches no provider.
    _seedFrom(session.lastRebasePlan);

    final List<RebaseTodoEntry> todo = _todo ?? const <RebaseTodoEntry>[];
    final RebaseTodoEntry? selected = todo
        .where((RebaseTodoEntry e) => e.oid == _selectedOid)
        .firstOrNull;
    final bool rebaseRunning = session.repoState?.isSequencerOperation ?? false;

    return GbmPanelTabShell(
      storageId: 'panel.interactiveRebase',
      detailIsEmpty: selected == null,
      emptyDetailMessage:
          'Select a commit to change what the rebase does '
          'with it',
      toolbar: PanelToolbarSpec(
        primary: <Widget>[
          // Starting needs a plan; a plan needs an upstream. Both come from
          // the list column, so this is only about whether one is loaded.
          GbmButton(
            label: 'Start',
            kind: GbmButtonKind.primary,
            onPressed: todo.isEmpty || rebaseRunning
                ? null
                : () => _session.startInteractiveRebase(
                    _upstreamController.text.trim(),
                    todo,
                  ),
          ),
        ],
        maintenance: <Widget>[
          // Only a rebase that is actually running can be aborted; offering
          // it otherwise would fail with git's own confusing error.
          //
          // It stays on the toolbar under rule 2 because it restores the
          // prior state rather than destroying work -- and it is the panel's
          // only escape hatch, so moving it to the detail action row would
          // hide the exit behind 「先選一個東西」. It keeps `danger` styling
          // anyway: not 破壞性 in rule 2's sense is not the same as
          // unremarkable.
          GbmButton(
            label: 'Abort',
            kind: GbmButtonKind.danger,
            onPressed: rebaseRunning ? _session.abortRebase : null,
          ),
          GbmButton(
            label: 'Reset order',
            kind: GbmButtonKind.ghost,
            onPressed: _todo == null
                ? null
                : () => setState(() {
                    _todo = List<RebaseTodoEntry>.of(_publishedPlan);
                    _selectedOid = null;
                  }),
          ),
        ],
        // Rule 3 makes this list writable, and a filtered order is not the
        // real order: dragging row 3 onto row 1 of a filtered view would
        // reorder against commits the user cannot see. Disabled with a
        // stated reason rather than hidden.
        filter: const PanelFilterField(
          query: '',
          onChanged: null,
          disabledReason: '重新排序要看得到完整順序，所以這裡不能篩選',
        ),
      ),
      listHeader: PanelListHeaderText(text: 'Commits · ${todo.length}'),
      statusBar: PanelStatusBarText(
        text: panelStatusLine(
          total: todo.length,
          shown: todo.length,
          noun: 'commit',
        ),
      ),
      list: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(GbmSpacing.space2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _upstreamController,
                    onSubmitted: (_) => _session.requestRebasePlan(
                      _upstreamController.text.trim(),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Upstream (e.g. main)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                GbmButton(
                  label: 'Load plan',
                  onPressed: () => _session.requestRebasePlan(
                    _upstreamController.text.trim(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: todo.isEmpty
                ? const PanelEmptyList(
                    message: 'Load a plan to see the commits it would replay',
                  )
                : ReorderableListView.builder(
                    itemCount: todo.length,
                    // The rebase replays oldest-first, so the list order is
                    // the execution order -- dragging a row is editing the
                    // todo file, which is the whole point of this panel.
                    // onReorderItem, not onReorder: it hands back a
                    // newIndex already adjusted for the removed item, so no
                    // off-by-one correction belongs here.
                    onReorderItem: (int oldIndex, int newIndex) => setState(() {
                      final List<RebaseTodoEntry> next =
                          List<RebaseTodoEntry>.of(todo);
                      next.insert(newIndex, next.removeAt(oldIndex));
                      _todo = next;
                    }),
                    itemBuilder: (context, i) => _TodoRow(
                      key: ValueKey<String>(todo[i].oid),
                      entry: todo[i],
                      selected: todo[i].oid == _selectedOid,
                      onTap: () => setState(() => _selectedOid = todo[i].oid),
                    ),
                  ),
          ),
        ],
      ),
      detail: selected == null
          ? const SizedBox.shrink()
          : PanelDetailColumn(
              children: <Widget>[
                PanelDetailField(
                  label: 'Commit',
                  value: '${selected.shortOid} · ${selected.subject}',
                  mono: true,
                ),
                const SizedBox(height: GbmSpacing.space2),
                // Material, because RadioListTile is a ListTile and paints
                // its ink on the nearest Material ancestor -- without one
                // the shell's own Container(color:) swallows the splash,
                // which Flutter asserts about rather than silently doing.
                // transparency keeps the shell's background visible.
                Material(
                  type: MaterialType.transparency,
                  child: RadioGroup<RebaseTodoAction>(
                    groupValue: selected.action,
                    onChanged: (RebaseTodoAction? next) {
                      if (next != null) _setAction(selected.oid, next);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final RebaseTodoAction action
                            in RebaseTodoAction.values)
                          RadioListTile<RebaseTodoAction>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: action,
                            title: Text(
                              _actionLabel(action),
                              style: TextStyle(
                                fontSize: GbmTypography.textSm,
                                color: context.gbmColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              _actionHelp(action),
                              style: TextStyle(
                                fontSize: GbmTypography.textXs,
                                color: context.gbmColors.textTertiary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

String _actionLabel(RebaseTodoAction action) => switch (action) {
  RebaseTodoAction.pick => 'Pick',
  RebaseTodoAction.edit => 'Edit',
  RebaseTodoAction.squash => 'Squash',
  RebaseTodoAction.fixup => 'Fixup',
  RebaseTodoAction.drop => 'Drop',
};

/// Spelled out because the consequences differ sharply and the verbs do not
/// say so: squash keeps both messages, fixup throws one away, drop loses the
/// change entirely.
String _actionHelp(RebaseTodoAction action) => switch (action) {
  RebaseTodoAction.pick => 'Replay this commit unchanged',
  RebaseTodoAction.edit =>
    'Stop here with the commit checked out, so it can be amended',
  RebaseTodoAction.squash =>
    'Combine into the previous commit, keeping both messages',
  RebaseTodoAction.fixup =>
    'Combine into the previous commit, discarding this message',
  RebaseTodoAction.drop => 'Leave this commit out entirely',
};

/// P19 list column: one line of the todo, draggable.
class _TodoRow extends StatelessWidget {
  const _TodoRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final RebaseTodoEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 54,
            child: Text(
              _actionLabel(entry.action).toLowerCase(),
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: entry.action == RebaseTodoAction.drop
                    ? colors.danger
                    : colors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 66,
            child: Text(
              entry.shortOid,
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.subject,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
