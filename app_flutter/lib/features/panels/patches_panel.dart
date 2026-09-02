import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/list_selection.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/services/file_save_picker.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_diff_text.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'patch_text_loader.dart';
import 'panel_widgets.dart';

/// One row of the patches list: either a `.patch` file on disk, or a commit
/// queued for export that has not been written yet.
///
/// P19's list column is 「.patch 檔或待建清單」 — literally "or", so the two
/// live in one list rather than two.
@immutable
class PatchRow {
  const PatchRow.file(this.path) : oid = '', subject = '';

  const PatchRow.pending({required this.oid, required this.subject})
    : path = '';

  /// Absolute path, empty for a pending row.
  final String path;

  /// Commit to export, empty for a file row.
  final String oid;
  final String subject;

  bool get isPending => path.isEmpty;
  String get title => isPending ? subject : path.split('/').last;
  String get subtitle => isPending ? 'To be created · $oid' : path;
  String get key => isPending ? 'pending:$oid' : 'file:$path';
}

/// `patches` as a tab (spec page 14 `IAMAP`), on page 19's template.
///
/// P19 `PANELSPEC` row:
/// - list: .patch 檔或待建清單
/// - detail: patch 內容 diff 預覽
/// - toolbar: Create from commits、Apply…、Save as
///
/// **Which segment each action lands in (P19 rule 2).** `Create from
/// commits` is the only one that creates a row, so it is primary. `Apply…`
/// and `Import…` both consume a patch into this repository — maintenance.
/// `Save as…` is the one action whose result leaves the app: it writes
/// `.patch` files into a directory the user picks, which is exactly what
/// rule 2's 「跳出去」 segment is for, and it is why this panel is one of the
/// few that draws the separator.
///
/// **Nothing moves to the detail action row**, because none of the four is
/// 破壞性 — the panel writes patches and applies them, and the only action
/// that changes the repository (`Apply…`/`Import…`) is undoable by the
/// sequencer controls the detail already shows mid-import.
///
/// **How the three toolbar actions divide up**, since the labels alone leave
/// room for more than one reading and this is the one implemented:
/// `Create from commits` queues the commits currently selected in History as
/// pending rows (the 待建清單 half of the list); `Save as` picks a directory
/// and writes them there, turning the pending rows into file rows; `Apply…`
/// opens the system picker (hence the ellipsis) and applies what is chosen,
/// adding those files to the list so the result can be read afterwards.
///
/// **The preview is [PanelDiffText], not `DiffPage`.** A `.patch` on disk was
/// never parsed — `ParsedDiff` only comes out of the C++ `UnifiedDiffParser`
/// via a diff request — so this colours git's text rather than pretending to
/// a structure it does not have. Nothing here can be staged, which is
/// correct for a read-only preview.
///
/// **`Import…` (`git am`) is a fourth button, on purpose.** It has no entry
/// point anywhere in the spec, and `gbm_patch_import`/`_continue`/`_skip`/
/// `_abort` would be four orphaned capi calls without it — the same call
/// manage-submodules makes for Add…/Deinit (#92). Its three sequencer buttons
/// only appear while an import is actually in progress; whether they belong
/// here or in P07's conflict banner, which carries the same three verbs for
/// rebase/cherry-pick/merge, is the open half of **#94**.
class PatchesPanel extends ConsumerStatefulWidget {
  const PatchesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<PatchesPanel> createState() => _PatchesPanelState();
}

class _PatchesPanelState extends ConsumerState<PatchesPanel> {
  final List<PatchRow> _rows = <PatchRow>[];
  String? _selectedKey;

  /// Cached per path so switching back to a row already read does not go to
  /// disk again, and so the detail pane has something to show synchronously.
  final Map<String, String> _text = <String, String>{};
  String? _loadError;
  String _query = '';

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  PatchRow? get _selected =>
      _rows.where((PatchRow r) => r.key == _selectedKey).firstOrNull;

  /// Matches **both** of a row's lines, which is what makes a directory
  /// segment findable: a file row's title is the base name and its subtitle
  /// is the whole path, so a title-only filter cannot answer 「which patches
  /// came out of `vendor/`?」. On a pending row the subtitle carries the oid,
  /// so the same predicate lets a commit be found by its hash.
  bool _matchesQuery(PatchRow row) {
    if (_query.trim().isEmpty) return true;
    final String needle = _query.trim().toLowerCase();
    return row.title.toLowerCase().contains(needle) ||
        row.subtitle.toLowerCase().contains(needle);
  }

  /// Rule 6's 「實際數量與耗時」, with **no 耗時 clause** -- the rows here are
  /// assembled in memory from a picker's result and a commit selection, so
  /// there is no scan to time.
  String _statusLine({required int total, required int shown}) =>
      panelStatusLine(
        total: total,
        shown: shown,
        noun: 'patch',
        nounPlural: 'patches',
      );

  void _addFiles(List<String> paths) {
    if (paths.isEmpty) return;
    setState(() {
      for (final String path in paths) {
        if (_rows.any((PatchRow r) => r.path == path)) continue;
        _rows.add(PatchRow.file(path));
      }
      _selectedKey = 'file:${paths.first}';
    });
    _loadText(paths.first);
  }

  Future<void> _loadText(String path) async {
    if (_text.containsKey(path)) return;
    try {
      final String text = await ref.read(patchTextLoaderProvider)(path);
      if (!mounted) return;
      setState(() {
        _text[path] = text;
        _loadError = null;
      });
    } on Object catch (error) {
      // A patch can be deleted or unreadable between being picked and being
      // previewed; saying so beats an empty pane that looks like an empty
      // patch.
      if (!mounted) return;
      setState(() => _loadError = '$error');
    }
  }

  Future<void> _apply() async {
    final List<String> paths = await ref
        .read(fileSavePickerProvider)
        .openFiles(extensions: const <String>['patch', 'diff']);
    if (paths.isEmpty || !mounted) return;
    _addFiles(paths);
    _session.applyPatchFiles(paths, threeWay: true, updateIndex: true);
  }

  Future<void> _import() async {
    final List<String> paths = await ref
        .read(fileSavePickerProvider)
        .openFiles(extensions: const <String>['patch', 'diff', 'mbox']);
    if (paths.isEmpty || !mounted) return;
    _addFiles(paths);
    _session.importPatches(paths, threeWay: true);
  }

  void _createFromCommits() {
    final ListSelection<String> selection = ref.read(
      commitSelectionProvider(widget.identity),
    );
    setState(() {
      for (final String oid in selection.items) {
        if (_rows.any((PatchRow r) => r.oid == oid)) continue;
        _rows.add(
          PatchRow.pending(
            oid: oid,
            subject:
                ref
                    .read(repoSessionProvider(widget.identity))
                    .commitMetaCache[oid]
                    ?.subject ??
                oid,
          ),
        );
      }
    });
  }

  Future<void> _saveAs() async {
    final List<String> oids = _rows
        .where((PatchRow r) => r.isPending)
        .map((PatchRow r) => r.oid)
        .toList(growable: false);
    if (oids.isEmpty) return;
    final String? dir = await ref.read(fileSavePickerProvider).pickDirectory();
    if (dir == null || !mounted) return;
    _session.exportPatches(oids, dir);
    // The files land asynchronously and the capi echoes back no paths, so
    // the pending rows stay pending rather than being renamed into file rows
    // this layer cannot verify exist.
  }

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final ListSelection<String> commits = ref.watch(
      commitSelectionProvider(widget.identity),
    );
    final bool importRunning = session.repoState?.isSequencerOperation ?? false;
    final PatchRow? selected = _selected;
    final bool hasPending = _rows.any((PatchRow r) => r.isPending);
    final List<PatchRow> visible = _rows
        .where(_matchesQuery)
        .toList(growable: false);

    return GbmPanelTabShell(
      storageId: 'panel.patches',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a patch to preview it',
      toolbar: PanelToolbarSpec(
        primary: <Widget>[
          GbmButton(
            label: 'Create from commits',
            kind: GbmButtonKind.primary,
            onPressed: commits.items.isEmpty ? null : _createFromCommits,
          ),
        ],
        maintenance: <Widget>[
          GbmButton(
            label: 'Apply…',
            kind: GbmButtonKind.ghost,
            onPressed: _apply,
          ),
          GbmButton(
            label: 'Import…',
            kind: GbmButtonKind.ghost,
            onPressed: _import,
          ),
        ],
        external: <Widget>[
          GbmButton(
            label: 'Save as…',
            kind: GbmButtonKind.ghost,
            onPressed: hasPending ? _saveAs : null,
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: (String value) => setState(() => _query = value),
        ),
      ),
      listHeader: PanelListHeaderText(text: 'Patches · ${visible.length}'),
      statusBar: PanelStatusBarText(
        text: _statusLine(total: _rows.length, shown: visible.length),
      ),
      list: visible.isEmpty
          ? PanelEmptyList(
              message: _rows.isNotEmpty
                  ? 'No patch matches the filter'
                  : commits.items.isEmpty
                  ? 'Select commits in History, or apply a .patch file'
                  : 'Create from commits to queue '
                        '${commits.items.length} selected commit(s)',
            )
          : ListView.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) => PanelListRow(
                title: visible[i].title,
                subtitle: visible[i].subtitle,
                selected: visible[i].key == _selectedKey,
                onTap: () {
                  setState(() => _selectedKey = visible[i].key);
                  if (!visible[i].isPending) _loadText(visible[i].path);
                },
              ),
            ),
      detail: selected == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (importRunning) _ImportControls(session: _session),
                Expanded(child: _buildPreview(context, selected)),
              ],
            ),
    );
  }

  Widget _buildPreview(BuildContext context, PatchRow row) {
    final GbmColors colors = context.gbmColors;
    if (row.isPending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(GbmSpacing.space4),
          child: Text(
            'Not written yet — use Save as… to export '
            '${row.oid} as a .patch file',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textTertiary,
            ),
          ),
        ),
      );
    }
    final String? text = _text[row.path];
    if (text == null) {
      return Center(
        child: _loadError == null
            ? const CircularProgressIndicator()
            : Text(
                'Could not read this patch: $_loadError',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.danger,
                ),
              ),
      );
    }
    return PanelDiffText(text: text);
  }
}

/// `git am`'s three ways forward, shown only while an import is actually in
/// progress -- offering them otherwise would fail with git's own error.
class _ImportControls extends StatelessWidget {
  const _ImportControls({required this.session});

  final RepoSessionController session;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      color: colors.surfacePanelRaised,
      padding: const EdgeInsets.all(GbmSpacing.space2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'An import is in progress',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          GbmButton(label: 'Continue', onPressed: session.continueImport),
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(label: 'Skip', onPressed: session.skipImport),
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(
            label: 'Abort',
            kind: GbmButtonKind.danger,
            onPressed: session.abortImport,
          ),
        ],
      ),
    );
  }
}
