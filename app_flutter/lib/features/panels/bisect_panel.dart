import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/bisect_status.dart';
import '../../data/models/commit_meta.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_widgets.dart';

/// `bisect` as a tab (spec page 14 `IAMAP`), on page 19's template. Reached
/// from Tools → Rewrite history ▸ Bisect… — P14 rule 2 keeps the
/// destructive/multi-step three out of the menu's top level.
///
/// P19 `PANELSPEC` row:
/// - list: 已標記的 good / bad 步驟
/// - detail: 目前待測 commit、剩餘步數、自訂測試指令
/// - toolbar: Good、Bad、Skip、Reset
///
/// Two of the three detail fields have no backing data and are absent
/// rather than faked:
///
/// - **剩餘步數.** git prints "Bisecting: N revisions left to test" on each
///   step, but [BisectStatus] does not carry it — `logText` is `git bisect
///   log`'s output (the `bisect replay` input), which has no such line. It
///   would need a new capi field, not a client-side derivation: the count
///   is `log2` of the *reachable* commits between good and bad, which this
///   layer cannot compute.
/// - **自訂測試指令.** That is `git bisect run <cmd>`, and `gbm_capi.h` has
///   start/mark/skip/reset only. Absent, tracked on #76.
///
/// **Which segment each action lands in (P19 rule 2), and why the primary
/// segment is empty.** Rule 2's first segment is 主要建立動作, and the only
/// action here that creates anything is `Start bisect` — which is not on the
/// toolbar (see below). Good / Bad / Skip / Reset all act on a bisect that
/// already exists, so they are all maintenance, and the primary segment is
/// simply empty. That is the intended reading of the four-segment rule: the
/// **order** is fixed, the **occupancy** is not, and an empty segment draws
/// no placeholder — which is what stops a read-only panel growing a fake
/// primary button.
///
/// `Reset` stays on the toolbar despite the danger styling: it ends the
/// bisect and puts HEAD back where it started, restoring a prior state
/// rather than destroying work, so rule 2's 破壞性 clause does not reach it.
/// Same ruling as interactive-rebase's `Abort`.
///
/// **The filter is live while a bisect runs and disabled when one is not.**
/// The list is a *record* of what has been marked — marking happens on the
/// toolbar, not in the list — so it is not one of rule 3's writable lists
/// and the 「篩過的順序不是真的順序」 objection that disables
/// interactive-rebase's filter does not apply here. **This corrects
/// [PanelFilterField]'s own doc comment**, which listed this panel with
/// interactive-rebase's writable ones. With no bisect running the list is a
/// start form instead, and there is nothing to filter.
///
/// **Start is not a toolbar button.** It only means anything when no bisect
/// is running, and it needs two refs, so it lives in the not-running
/// state's own form — the same call [LfsPanel] makes for `Install`.
class BisectPanel extends ConsumerStatefulWidget {
  const BisectPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<BisectPanel> createState() => _BisectPanelState();
}

class _BisectPanelState extends ConsumerState<BisectPanel> {
  final TextEditingController _badController = TextEditingController();
  final TextEditingController _goodController = TextEditingController();
  String _query = '';
  String? _selectedOid;

  @override
  void initState() {
    super.initState();
    Future.microtask(_session.refreshBisectStatus);
  }

  @override
  void dispose() {
    _badController.dispose();
    _goodController.dispose();
    super.dispose();
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  /// Selecting a step is also what asks for its subject, for the same reason
  /// [WorktreesPanel] does: nothing else fills this cache for a commit the
  /// History viewport never scrolled past, so the detail would show a bare
  /// oid forever. Gated on the cache so re-selecting costs nothing.
  void _select(String oid, Map<String, CommitMeta> metas) {
    setState(() => _selectedOid = oid);
    if (metas.containsKey(oid)) return;
    _session.requestCommitMeta(<String>[oid]);
  }

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final BisectStatus status = session.bisectStatus;
    final List<BisectStep> steps = bisectSteps(status, context.gbmColors);
    final List<BisectStep> visible = steps
        .where(
          (BisectStep s) =>
              _query.trim().isEmpty ||
              s.oid.toLowerCase().contains(_query.trim().toLowerCase()) ||
              s.mark.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList(growable: false);
    final BisectStep? selected = visible
        .where((BisectStep s) => s.oid == _selectedOid)
        .firstOrNull;

    return GbmPanelTabShell(
      storageId: 'panel.bisect',
      detailIsEmpty: !status.active,
      emptyDetailMessage: 'No bisect in progress',
      toolbar: PanelToolbarSpec(
        // Good/Bad/Skip all act on HEAD -- the commit git checked out for
        // this step -- so they need no selection, only a running bisect.
        maintenance: <Widget>[
          GbmButton(
            label: 'Good',
            kind: GbmButtonKind.ghost,
            onPressed: status.active
                ? () => _session.markBisect(good: true)
                : null,
          ),
          GbmButton(
            label: 'Bad',
            kind: GbmButtonKind.ghost,
            onPressed: status.active
                ? () => _session.markBisect(good: false)
                : null,
          ),
          GbmButton(
            label: 'Skip',
            kind: GbmButtonKind.ghost,
            onPressed: status.active ? () => _session.skipBisect() : null,
          ),
          GbmButton(
            label: 'Reset',
            kind: GbmButtonKind.danger,
            onPressed: status.active ? () => _session.resetBisect() : null,
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: status.active
              ? (String value) => setState(() => _query = value)
              : null,
          disabledReason: '還沒開始 bisect，沒有已標記的步驟可以篩選',
        ),
      ),
      listHeader: PanelListHeaderText(text: 'Marked steps · ${visible.length}'),
      statusBar: PanelStatusBarText(
        text: panelStatusLine(
          total: steps.length,
          shown: visible.length,
          noun: 'step',
        ),
      ),
      list: status.active
          ? _MarkedSteps(
              steps: visible,
              selectedOid: _selectedOid,
              onSelect: (String oid) => _select(oid, session.commitMetaCache),
            )
          : _StartForm(
              badController: _badController,
              goodController: _goodController,
              onStart: () {
                final String bad = _badController.text.trim();
                final String good = _goodController.text.trim();
                _session.startBisect(
                  badRef: bad,
                  goodRefs: good.isEmpty ? const <String>[] : <String>[good],
                );
              },
            ),
      detail: !status.active
          ? const SizedBox.shrink()
          : _BisectDetail(
              status: status,
              selected: selected,
              meta: session.commitMetaCache[selected?.oid ?? status.currentOid],
            ),
    );
  }
}

/// One row of the marked-steps list.
///
/// A named type rather than an inline record because the panel now needs the
/// same list three times over -- to count, to filter, and to resolve the
/// selection back to a mark -- and deriving it three ways is how the three
/// disagree ([CULT-single-source-of-truth]).
@immutable
class BisectStep {
  const BisectStep({
    required this.oid,
    required this.mark,
    required this.color,
  });

  final String oid;
  final String mark;
  final Color color;
}

/// The marked steps in the order the panel lists them: the bad tip, then the
/// good commits, then the skipped ones.
List<BisectStep> bisectSteps(BisectStatus status, GbmColors colors) =>
    <BisectStep>[
      if (status.badOid.isNotEmpty)
        BisectStep(oid: status.badOid, mark: 'bad', color: colors.danger),
      for (final String oid in status.goodOids)
        BisectStep(oid: oid, mark: 'good', color: colors.success),
      for (final String oid in status.skippedOids)
        BisectStep(oid: oid, mark: 'skipped', color: colors.textTertiary),
    ];

/// P19 list column: 已標記的 good / bad 步驟.
///
/// These rows were a bare `Padding` + `Row` until this round, so they had
/// none of rule 3's shape and could not be selected at all -- this was the
/// one panel of the twelve whose left list did not drive its right detail,
/// which is P19's entire shape.
class _MarkedSteps extends StatelessWidget {
  const _MarkedSteps({
    required this.steps,
    required this.selectedOid,
    required this.onSelect,
  });

  final List<BisectStep> steps;
  final String? selectedOid;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const PanelEmptyList(
        message: 'Nothing marked yet — test HEAD and mark it good or bad',
      );
    }

    return ListView.builder(
      itemCount: steps.length,
      itemBuilder: (context, i) => PanelListRow(
        title: steps[i].oid,
        subtitle: steps[i].mark,
        subtitleColor: steps[i].color,
        selected: steps[i].oid == selectedOid,
        onTap: () => onSelect(steps[i].oid),
      ),
    );
  }
}

/// P19 detail column: 目前待測 commit (剩餘步數 and 自訂測試指令 have no
/// backing data -- see [BisectPanel]'s class doc).
class _BisectDetail extends StatelessWidget {
  const _BisectDetail({
    required this.status,
    required this.selected,
    required this.meta,
  });

  final BisectStatus status;
  final BisectStep? selected;
  final CommitMeta? meta;

  @override
  Widget build(BuildContext context) {
    final BisectStep? step = selected;
    return PanelDetailColumn(
      children: <Widget>[
        // Per-item fields swap with the selection; the session-level ones
        // below describe the bisect as a whole and survive it. Without a
        // selection the item *is* HEAD, which is what the panel is for.
        if (step == null)
          PanelDetailField(
            label: 'Now testing',
            value: status.currentOid.isEmpty
                ? 'Waiting for a good and a bad commit'
                : status.currentOid,
            mono: true,
          )
        else ...<Widget>[
          PanelDetailField(label: 'Commit', value: step.oid, mono: true),
          PanelDetailField(label: 'Marked', value: step.mark),
        ],
        if (meta != null)
          PanelDetailField(label: 'Subject', value: meta!.subject),
        PanelDetailField(
          label: 'Marked so far',
          value:
              '${status.goodOids.length} good · '
              '${status.badOid.isEmpty ? 0 : 1} bad · '
              '${status.skippedOids.length} skipped',
        ),
        if (status.logText.trim().isNotEmpty)
          PanelDetailField(label: 'Bisect log', value: status.logText.trim()),
      ],
    );
  }
}

/// Shown while no bisect is running. Starting one needs a known-bad and a
/// known-good ref, which is a form rather than a toolbar action.
class _StartForm extends StatelessWidget {
  const _StartForm({
    required this.badController,
    required this.goodController,
    required this.onStart,
  });

  final TextEditingController badController;
  final TextEditingController goodController;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GbmSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'No bisect in progress',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          TextField(
            controller: badController,
            decoration: const InputDecoration(
              labelText: 'Known bad (empty = HEAD)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          TextField(
            controller: goodController,
            decoration: const InputDecoration(
              labelText: 'Known good',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          // Starting with no good ref at all is valid -- git waits for the
          // first `bisect good` -- so this is never disabled on input.
          GbmButton(
            label: 'Start bisect',
            kind: GbmButtonKind.primary,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}
