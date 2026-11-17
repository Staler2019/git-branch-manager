import 'package:flutter/material.dart';
import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';
import 'package:gbm_flutter/features/panels/panel_storage_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/git_error.dart';
import '../../data/models/keyed_read_reply.dart';
import '../../data/models/line_history_chunk.dart';
import '../../data/models/list_selection.dart';
import '../../data/models/read_keys.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_banner.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_open_log_button.dart';
import '../history_graph/widgets/graph_date_format.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_diff_text.dart';
import 'panel_widgets.dart';

/// `line-history` as a tab (spec page 14 `IAMAP`), on page 19's template.
/// Opened per file from 05-F's `History ▸ Line history…`.
///
/// P19 `PANELSPEC` row:
/// - list: 選定行區的演化
/// - detail: 每一步的前後對照
/// - toolbar: 擴大行區、跳到 commit
///
/// **Which segment each action lands in (P19 rule 2), and why the primary
/// segment is empty.** A line history creates nothing. `Widen range`
/// changes what *this panel* shows, so it is maintenance; only
/// `Go to commit` is 「跳出去」.
///
/// **The filter is live, and this round's plan predicted it would not be.**
/// The plan grouped this panel with `blame` as 「左清單是檔案內容而不是具名
/// 集合」 — but a [LineHistoryChunk] carries `oid`, `author` and `subject`,
/// and the row draws a subject over an author and a date. That is
/// `file-history`'s shape, not blame's raw file lines, so there is a name
/// to match and no order a filter could falsify
/// ([CULT-scrutinise-the-comment]: the premise did not survive the source).
///
/// The detail is [PanelDiffText], not `DiffPage`: `LineHistoryChunk.diffText`
/// is git's own `log -L` output as text, and nothing on this side parses a
/// diff into the structure `DiffPage` needs.
///
/// **The line range is a control, not an action.** `PANELSPEC` names two
/// actions, and which lines this panel is *about* is the list's scope, so
/// the two range fields sit above the list — the same call [ReflogPanel]
/// makes for its ref selector. 擴大行區 is the toolbar button that widens
/// that range without retyping it.
class LineHistoryPanel extends ConsumerStatefulWidget {
  const LineHistoryPanel({
    super.key,
    required this.identity,
    required this.path,
    this.initialStartLine = 1,
    this.initialEndLine = 1,
  });

  final RepoIdentity identity;
  final String path;

  /// Both are **parsed by `panel_page.dart` but produced by nothing** under
  /// `lib/` today, and are read in `initState` only — so a second open of
  /// the same file focuses the existing tab and silently keeps the old
  /// range. Wiring a producer therefore also needs a `didUpdateWidget`; the
  /// two must land together. Tracked as **#95**.
  final int initialStartLine;
  final int initialEndLine;

  @override
  ConsumerState<LineHistoryPanel> createState() => _LineHistoryPanelState();
}

class _LineHistoryPanelState extends ConsumerState<LineHistoryPanel> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  int? _selectedIndex;
  String _query = '';

  /// How many lines each side of the range `Widen` adds. Small enough that
  /// a second press is a deliberate act rather than a jump to the whole
  /// file, which would defeat the point of a line history.
  static const int _kWidenBy = 10;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(
      text: '${widget.initialStartLine}',
    );
    _endController = TextEditingController(text: '${widget.initialEndLine}');
    _send(_fieldsKey(), fromLifecycle: true);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  int get _start => int.tryParse(_startController.text.trim()) ?? 1;
  int get _end => int.tryParse(_endController.text.trim()) ?? _start;

  /// The range the fields say now. Read only at send time: what is typed but
  /// not submitted is not a request.
  LineHistoryKey _fieldsKey() =>
      LineHistoryKey(path: widget.path, startLine: _start, endLine: _end);

  /// The request this panel last sent. The session's
  /// [RepoSessionState.lastLineHistory] is drawn -- content and failure banner
  /// alike -- only while its key is this one: the mount's send reaches the
  /// controller a microtask late, and the frame in between must not show
  /// another range (read-failure-states-spec.html, ruling 4).
  LineHistoryKey? _sentKey;

  /// Every send goes through here, so [_sentKey] is always the request the
  /// controller was last asked for. From a lifecycle method the controller
  /// call is deferred: a provider write during build throws.
  void _send(LineHistoryKey key, {bool fromLifecycle = false}) {
    _sentKey = key;
    void request() => _session.requestLineHistory(
      key.path,
      key.startLine,
      key.endLine,
      startRevision: key.startRevision,
    );
    if (fromLifecycle) {
      Future.microtask(request);
    } else {
      request();
    }
  }

  void _request() {
    setState(() => _selectedIndex = null);
    _send(_fieldsKey());
  }

  void _widen() {
    // git's line numbers are 1-based, so the start clamps at 1 rather than
    // at 0 -- asking for line 0 is an error, not "the beginning".
    _startController.text = '${(_start - _kWidenBy).clamp(1, _start)}';
    _endController.text = '${_end + _kWidenBy}';
    _request();
  }

  /// Matches the subject, the author's name **and the oid**, though the row
  /// draws only the first two -- the same reasoning as `reflog` and
  /// `file-history`: a hash pasted out of git's own output has nowhere else
  /// to go.
  bool _matchesQuery(LineHistoryChunk chunk) {
    if (_query.trim().isEmpty) return true;
    final String needle = _query.trim().toLowerCase();
    return chunk.subject.toLowerCase().contains(needle) ||
        chunk.author.name.toLowerCase().contains(needle) ||
        chunk.oid.toLowerCase().contains(needle);
  }

  @override
  Widget build(BuildContext context) {
    final KeyedReadReply<LineHistoryKey, List<LineHistoryChunk>>? reply = ref
        .watch(
          repoSessionProvider(widget.identity).select((s) => s.lastLineHistory),
        );
    final bool answersThisPanel = reply != null && reply.key == _sentKey;
    final List<LineHistoryChunk> chunks =
        (answersThisPanel ? reply.value : null) ?? const <LineHistoryChunk>[];
    final GitError? error = answersThisPanel ? reply.error : null;
    final List<LineHistoryChunk> visible = chunks
        .where(_matchesQuery)
        .toList(growable: false);
    final LineHistoryChunk? selected =
        (_selectedIndex != null && _selectedIndex! < chunks.length)
        ? chunks[_selectedIndex!]
        : null;

    return GbmPanelTabShell(
      // P19 樣板規則 1's 「各自記憶…splitter」. Suffixed with the subject
      // because this is one of the three kinds that can be open twice at
      // once: on a bare `panel.<kind>` id, resizing one tab silently
      // resizes the other. The nine singleton kinds keep their unsuffixed
      // ids -- re-keying those would orphan every saved size to buy a
      // distinction that cannot arise.
      storageId: panelStorageId(GbmPanelKind.lineHistory, subject: widget.path),
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a step to see its before/after',
      banner: error == null
          ? null
          : GbmWarningBanner(
              message: '無法載入 ${widget.path} 的 line history。${error.message}',
              action: const GbmOpenLogButton(),
            ),
      toolbar: PanelToolbarSpec(
        maintenance: <Widget>[
          GbmButton(
            label: 'Widen range',
            kind: GbmButtonKind.ghost,
            onPressed: _widen,
          ),
        ],
        external: <Widget>[
          GbmButton(
            label: 'Go to commit',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () => _goToCommit(context, selected.oid),
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: (String value) => setState(() => _query = value),
        ),
      ),
      listHeader: PanelListHeaderText(text: 'Commits · ${visible.length}'),
      statusBar: PanelStatusBarText(
        text: panelStatusLine(
          total: chunks.length,
          shown: visible.length,
          noun: 'commit',
        ),
      ),
      list: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _RangeFields(
            startController: _startController,
            endController: _endController,
            onSubmit: _request,
          ),
          Expanded(
            child: visible.isEmpty
                ? PanelEmptyList(
                    message: chunks.isEmpty
                        ? 'No commits touched these lines'
                        : 'No commit matches the filter',
                  )
                : ListView.builder(
                    // Own scroll-memory slot (expectDistinctScrollStorage).
                    key: const PageStorageKey<String>('panel-list'),
                    itemCount: visible.length,
                    itemBuilder: (context, i) => PanelListRow(
                      title: visible[i].subject,
                      subtitle:
                          '${visible[i].author.name} · '
                          '${formatGraphDate(DateTime.fromMillisecondsSinceEpoch(visible[i].author.when * 1000), DateTime.now())}',
                      // The selection is keyed on the *unfiltered* index, so
                      // narrowing the list never silently moves it onto a
                      // different commit.
                      selected: chunks.indexOf(visible[i]) == _selectedIndex,
                      onTap: () => setState(
                        () => _selectedIndex = chunks.indexOf(visible[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      detail: selected == null
          ? const SizedBox.shrink()
          : PanelDiffText(text: selected.diffText),
    );
  }

  /// Selects [oid] in History and navigates there. Selecting *before*
  /// navigating means the graph is already scrolled to the right row on its
  /// first build rather than jumping a frame later.
  void _goToCommit(BuildContext context, String oid) {
    ref.read(commitSelectionProvider(widget.identity).notifier).state =
        const ListSelection<String>().single(oid);
    context.go(
      RoutePaths.historyFor(Uri.encodeComponent(widget.identity.workDir)),
    );
  }
}

class _RangeFields extends StatelessWidget {
  const _RangeFields({
    required this.startController,
    required this.endController,
    required this.onSubmit,
  });

  final TextEditingController startController;
  final TextEditingController endController;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GbmSpacing.space2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              // Own scroll-memory slot (expectDistinctScrollStorage).
              key: const PageStorageKey<String>('panel-field:start'),
              controller: startController,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                labelText: 'From line',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          Expanded(
            child: TextField(
              // Own scroll-memory slot (expectDistinctScrollStorage).
              key: const PageStorageKey<String>('panel-field:end'),
              controller: endController,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                labelText: 'To line',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(label: 'Load', onPressed: onSubmit),
        ],
      ),
    );
  }
}
