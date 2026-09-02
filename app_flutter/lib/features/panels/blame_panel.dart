import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/blame_result.dart';
import '../../data/models/commit_meta.dart';
import '../../data/models/list_selection.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../widgets/code_line_metrics.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_code_hscroll.dart';
import '../../widgets/gbm_row.dart';
import '../history_graph/widgets/graph_date_format.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_widgets.dart';

/// `blame` as a tab (spec page 14 `IAMAP`), on page 19's template. Opened
/// per file from 05-F's `History ▸ Blame…`.
///
/// P19 `PANELSPEC` row:
/// - list: 檔案內容（每行帶作者）
/// - detail: 選到的行對應的 commit 明細
/// - toolbar: 上一版、忽略空白、跳到 commit
///
/// **Which segment each action lands in (P19 rule 2), and why the primary
/// segment is empty.** Nothing in a blame view creates anything — it is a
/// read-only surface — so the 主要建立動作 segment is simply empty, and an
/// empty segment draws no placeholder. That is what stops a read-only panel
/// growing a fake primary button.
///
/// `Previous revision` and `Ignore whitespace` are both maintenance: each
/// changes what *this panel* shows. Only `Go to commit` is 「跳出去」 — it
/// navigates to History — which is the very example [PanelToolbarSpec]'s
/// own doc gives for that segment.
///
/// **The filter is disabled with a stated reason.** Rule 2 pins a filter to
/// the toolbar's right end for every panel, but this list is *file content*
/// rather than a named collection, so there is nothing a name filter could
/// match. Disabled beats hidden — 隱藏會讓人以為功能不存在.
///
/// **「忽略空白」 renders disabled.** `gbm_request_blame` takes path,
/// revision and a line range — there is no `-w`. Disabled with the reason
/// rather than hidden, the same call [RemotesPanel] makes for `Edit…`, and
/// tracked on #76 as a capi gap.
///
/// **「上一版」 needs the selected line's commit's parent**, which is not in
/// [BlameLine] — only the commit's own oid is. So it requests that commit's
/// metadata on selection and enables itself once `parents` has arrived;
/// until then it is disabled rather than guessing a revision.
/// Width of a blame row's pinned gutter: the row's own left padding, the
/// line-number cell, the author cell and the gaps between them.
const double kBlameGutterWidth =
    GbmSpacing.space2 + 44 + GbmSpacing.space2 + 90 + GbmSpacing.space2;

/// The style a blame row's code is drawn in, colour aside. Measured in it,
/// then drawn in it -- see `kDiffCodeTextStyle` for why that has to be one
/// constant.
const TextStyle kBlameCodeTextStyle = TextStyle(
  fontFamily: GbmTypography.fontMono,
  fontSize: GbmTypography.textXs,
);

class BlamePanel extends ConsumerStatefulWidget {
  const BlamePanel({super.key, required this.identity, required this.path});

  final RepoIdentity identity;
  final String path;

  @override
  ConsumerState<BlamePanel> createState() => _BlamePanelState();
}

class _BlamePanelState extends ConsumerState<BlamePanel> {
  int? _selectedLine;

  /// Keyed by the `List<BlameLine>` currently shown -- a new blame result is
  /// a new list, so the key is the invalidation. See [CodeWidthMemo].
  final CodeWidthMemo _widthMemo = CodeWidthMemo();

  /// Owned here so [GbmCodeHScroll] can paint the vertical scrollbar on the
  /// pane's box instead of on the content's; the same instance drives the
  /// list below.
  final ScrollController _vertical = ScrollController();

  /// Empty means the working-tree version, which is what
  /// `gbm_request_blame` treats an empty revision as. Walking back with
  /// 上一版 sets it.
  String _revision = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _session.requestBlame(widget.path));
  }

  @override
  void dispose() {
    _vertical.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(BlamePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) {
      setState(() {
        _selectedLine = null;
        _revision = '';
      });
      _session.requestBlame(widget.path);
    }
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  void _select(BlameLine line) {
    setState(() => _selectedLine = line.finalLine);
    _session.requestCommitMeta(<String>[line.commitOid]);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool softWrap = ref.watch(appPreferencesProvider).softWrapEnabled;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final BlameResult? blame = session.lastBlame;
    final List<BlameLine> lines = blame?.lines ?? const <BlameLine>[];
    final BlameLine? selected = lines
        .where((BlameLine l) => l.finalLine == _selectedLine)
        .firstOrNull;
    final CommitMeta? meta = selected == null
        ? null
        : session.commitMetaCache[selected.commitOid];
    final String? parent = (meta != null && meta.parents.isNotEmpty)
        ? meta.parents.first
        : null;

    return GbmPanelTabShell(
      // P19 樣板規則 1's 「各自記憶…splitter」. Suffixed with the subject
      // because this is one of the three kinds that can be open twice at
      // once: on a bare `panel.<kind>` id, resizing one tab silently
      // resizes the other. The nine singleton kinds keep their unsuffixed
      // ids -- re-keying those would orphan every saved size to buy a
      // distinction that cannot arise.
      storageId: 'panel.blame:${widget.path}',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a line to see the commit that wrote it',
      toolbar: PanelToolbarSpec(
        maintenance: <Widget>[
          GbmButton(
            label: 'Previous revision',
            kind: GbmButtonKind.ghost,
            onPressed: parent == null
                ? null
                : () {
                    setState(() {
                      _revision = parent;
                      _selectedLine = null;
                    });
                    _session.requestBlame(widget.path, revision: parent);
                  },
          ),
          const Tooltip(
            message: 'Ignoring whitespace is not supported yet',
            child: GbmButton(
              label: 'Ignore whitespace',
              kind: GbmButtonKind.ghost,
              onPressed: null,
            ),
          ),
        ],
        external: <Widget>[
          GbmButton(
            label: 'Go to commit',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () {
                    ref
                        .read(commitSelectionProvider(widget.identity).notifier)
                        .state = const ListSelection<String>().single(
                      selected.commitOid,
                    );
                    context.go(
                      RoutePaths.historyFor(
                        Uri.encodeComponent(widget.identity.workDir),
                      ),
                    );
                  },
          ),
        ],
        filter: const PanelFilterField(
          query: '',
          onChanged: null,
          disabledReason: '這個清單是檔案內容，沒有可以篩選的名稱',
        ),
      ),
      listHeader: PanelListHeaderText(text: 'Lines · ${lines.length}'),
      statusBar: PanelStatusBarText(
        text: panelStatusLine(
          total: lines.length,
          shown: lines.length,
          noun: 'line',
        ),
      ),
      list: lines.isEmpty
          ? const PanelEmptyList(message: 'No blame information')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_revision.isNotEmpty) _RevisionBanner(revision: _revision),
                if (blame?.truncated ?? false)
                  const _RevisionBanner(
                    revision: 'Truncated — not every line is shown',
                  ),
                Expanded(
                  child: GbmCodeHScroll(
                    contentWidth: softWrap
                        ? 0
                        : kBlameGutterWidth +
                              _widthMemo.widthOf(
                                key: lines,
                                text: () => <String>[
                                  for (final BlameLine l in lines) l.content,
                                ].join('\n'),
                                style: kBlameCodeTextStyle,
                              ) +
                              GbmSpacing.space2,
                    verticalController: _vertical,
                    backdrop: colors.surfacePanel,
                    child: ListView.builder(
                      controller: _vertical,
                      itemCount: lines.length,
                      itemBuilder: (context, i) => _BlameLineRow(
                        line: lines[i],
                        selected: lines[i].finalLine == _selectedLine,
                        onTap: () => _select(lines[i]),
                        softWrap: softWrap,
                      ),
                    ),
                  ),
                ),
              ],
            ),
      detail: selected == null
          ? const SizedBox.shrink()
          : PanelDetailColumn(
              children: <Widget>[
                PanelDetailField(label: 'Line', value: '${selected.finalLine}'),
                PanelDetailField(
                  label: 'Commit',
                  value: selected.commitOid,
                  mono: true,
                ),
                PanelDetailField(label: 'Subject', value: selected.summary),
                PanelDetailField(
                  label: 'Author',
                  value:
                      '${selected.authorName} <${selected.authorEmail}> · '
                      '${formatGraphDate(DateTime.fromMillisecondsSinceEpoch(selected.authorTime * 1000), DateTime.now())}',
                ),
                if (meta != null && meta.body.trim().isNotEmpty)
                  PanelDetailField(label: 'Body', value: meta.body.trim()),
                // A boundary line predates the blame's range, so there is
                // nothing earlier to walk back to for it.
                if (selected.boundary)
                  const PanelDetailField(
                    label: 'Boundary',
                    value: 'This line comes from before the blamed range',
                  ),
              ],
            ),
    );
  }
}

/// P19 list column: 檔案內容（每行帶作者）.
class _BlameLineRow extends StatelessWidget {
  const _BlameLineRow({
    required this.line,
    required this.selected,
    required this.onTap,
    required this.softWrap,
  });

  final BlameLine line;
  final bool selected;
  final VoidCallback onTap;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      selected: selected,
      onTap: onTap,
      // With wrapping off the left padding moves *inside* the pinned gutter,
      // so the gutter covers everything the code could otherwise scroll into.
      padding: EdgeInsets.only(
        left: softWrap ? GbmSpacing.space2 : 0,
        right: GbmSpacing.space2,
      ),
      child: softWrap ? _wrapped(colors) : _scrolling(colors),
    );
  }

  /// Today's layout: the code shares the row with the gutter and wraps.
  ///
  /// The `maxLines: 1` + ellipsis this used to carry unconditionally is gone.
  /// It predates the preference and was never a choice -- a blame line simply
  /// got cut off, with no way to see the rest.
  Widget _wrapped(GbmColors colors) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _gutterCells(colors),
      Expanded(
        child: Text(
          line.content,
          style: kBlameCodeTextStyle.copyWith(color: colors.textPrimary),
        ),
      ),
    ],
  );

  /// Gutter pinned, code scrolling underneath.
  ///
  /// `opaque: false` plus [GbmPinnedGutterClip], not an opaque strip: the
  /// background here belongs to the enclosing [GbmRow] -- its hover and
  /// selection tints -- and a gutter that repainted the panel's surface over
  /// them would kill both, at every scroll offset including zero.
  Widget _scrolling(GbmColors colors) => Stack(
    children: <Widget>[
      GbmPinnedGutterClip(
        gutterWidth: kBlameGutterWidth,
        child: Padding(
          padding: const EdgeInsets.only(left: kBlameGutterWidth),
          child: Text(
            line.content,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: kBlameCodeTextStyle.copyWith(color: colors.textPrimary),
          ),
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: GbmPinnedGutter(
          width: kBlameGutterWidth,
          background: null,
          opaque: false,
          child: Padding(
            padding: const EdgeInsets.only(left: GbmSpacing.space2),
            child: _gutterCells(colors),
          ),
        ),
      ),
    ],
  );

  Widget _gutterCells(GbmColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 44,
          child: Text(
            '${line.finalLine}',
            textAlign: TextAlign.right,
            style: kBlameCodeTextStyle.copyWith(color: colors.textTertiary),
          ),
        ),
        const SizedBox(width: GbmSpacing.space2),
        SizedBox(
          width: 90,
          child: Text(
            line.authorName,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: GbmSpacing.space2),
      ],
    );
  }
}

/// Says which revision the list is showing once 上一版 has walked back from
/// the working tree -- without it the panel silently stops being about the
/// file on disk.
class _RevisionBanner extends StatelessWidget {
  const _RevisionBanner({required this.revision});

  final String revision;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space1,
      ),
      color: colors.surfacePanelRaised,
      child: Text(
        revision.contains(' ') ? revision : 'Showing revision $revision',
        style: TextStyle(
          fontSize: GbmTypography.textXs,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
