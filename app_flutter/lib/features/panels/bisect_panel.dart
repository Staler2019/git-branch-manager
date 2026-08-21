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

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final BisectStatus status = session.bisectStatus;

    return GbmPanelTabShell(
      storageId: 'panel.bisect',
      detailIsEmpty: !status.active,
      emptyDetailMessage: 'No bisect in progress',
      toolbar: <Widget>[
        // Good/Bad/Skip all act on HEAD -- the commit git checked out for
        // this step -- so they need no selection, only a running bisect.
        GbmButton(
          label: 'Good',
          onPressed: status.active
              ? () => _session.markBisect(good: true)
              : null,
        ),
        GbmButton(
          label: 'Bad',
          onPressed: status.active
              ? () => _session.markBisect(good: false)
              : null,
        ),
        GbmButton(
          label: 'Skip',
          onPressed: status.active ? () => _session.skipBisect() : null,
        ),
        GbmButton(
          label: 'Reset',
          kind: GbmButtonKind.danger,
          onPressed: status.active ? () => _session.resetBisect() : null,
        ),
      ],
      list: status.active
          ? _MarkedSteps(status: status)
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
              meta: session.commitMetaCache[status.currentOid],
            ),
    );
  }
}

/// P19 list column: 已標記的 good / bad 步驟.
class _MarkedSteps extends StatelessWidget {
  const _MarkedSteps({required this.status});

  final BisectStatus status;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<({String oid, String mark, Color color})> rows =
        <({String oid, String mark, Color color})>[
          if (status.badOid.isNotEmpty)
            (oid: status.badOid, mark: 'bad', color: colors.danger),
          for (final String oid in status.goodOids)
            (oid: oid, mark: 'good', color: colors.success),
          for (final String oid in status.skippedOids)
            (oid: oid, mark: 'skipped', color: colors.textTertiary),
        ];

    if (rows.isEmpty) {
      return const PanelEmptyList(
        message: 'Nothing marked yet — test HEAD and mark it good or bad',
      );
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GbmSpacing.space3,
          vertical: GbmSpacing.space1,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                rows[i].oid,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  fontFamily: GbmTypography.fontMono,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: GbmSpacing.space2),
            Text(
              rows[i].mark,
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: rows[i].color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// P19 detail column: 目前待測 commit (剩餘步數 and 自訂測試指令 have no
/// backing data -- see [BisectPanel]'s class doc).
class _BisectDetail extends StatelessWidget {
  const _BisectDetail({required this.status, required this.meta});

  final BisectStatus status;
  final CommitMeta? meta;

  @override
  Widget build(BuildContext context) {
    return PanelDetailColumn(
      children: <Widget>[
        PanelDetailField(
          label: 'Now testing',
          value: status.currentOid.isEmpty
              ? 'Waiting for a good and a bad commit'
              : status.currentOid,
          mono: true,
        ),
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
