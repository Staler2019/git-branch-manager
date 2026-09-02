import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/lfs_state.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import 'gbm_panel_tab_shell.dart';
import 'lfs_pattern_match.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_widgets.dart';

/// `manage-lfs` as a tab (spec page 14 `IAMAP`), on page 19's template.
///
/// P19 `PANELSPEC` row:
/// - list: 追蹤型別 + 檔數 + 大小
/// - detail: 對應檔案、本地快取狀態
/// - toolbar: Track、Untrack、Fetch、Prune
///
/// **大小 is absent.** [LfsFileInfo] carries `path`, `oid` and
/// `downloadedLocally` — no byte count — and `gbm_capi.h` has no LFS size
/// call. Absent rather than faked, the 待提交數 precedent.
///
/// **檔數 is derived**, since nothing reports which pattern claimed which
/// file: the two capi lists are independent, so [lfsPatternMatches] groups
/// them here. That matcher is an approximation of gitattributes — read its
/// doc before trusting an unusual pattern's count.
///
/// **`Pull` is a fifth toolbar button, on purpose.** `git lfs fetch` (the
/// spec'd action) only fills the local object cache; without `git lfs pull`
/// the working tree keeps its pointer files, so Fetch alone leaves the
/// repository unusable for LFS content. `gbm_lfs_pull` exists and has no
/// entry point anywhere else in the spec — same call as manage-submodules'
/// Add…/Deinit (#92). Tracked as **#93**.
///
/// **Which segment each action lands in (P19 rule 2).** `Track…` is the only
/// action that creates anything, so it is the primary one. `Fetch`, `Prune`
/// and `Pull` all act on the local object cache for the repository as a
/// whole -- maintenance, and none of them needs a selection. There is no
/// 「跳出去」 segment: nothing here opens an external tool.
///
/// `Untrack` moves to the detail action row, because rule 2 keeps 破壞性
/// 動作 off the toolbar. It qualifies on the same 「拿不回來」 boundary that
/// moves stashes' `Drop` and submodules' `Deinit`: untracking rewrites
/// `.gitattributes` and leaves the pattern's objects as plain files, which
/// no single action puts back. `Prune` stays despite deleting objects --
/// it only removes cache entries git can fetch again.
///
/// **`Install` is not a toolbar button.** It only means anything when LFS
/// is not installed, and it appears in that state's own message instead —
/// a permanently-irrelevant button is noise, where a state that explains
/// itself and offers the one fix is not.
class LfsPanel extends ConsumerStatefulWidget {
  const LfsPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<LfsPanel> createState() => _LfsPanelState();
}

class _LfsPanelState extends ConsumerState<LfsPanel> {
  String? _selectedPattern;
  bool _trackExpanded = false;
  String _query = '';
  final TextEditingController _patternController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_session.refreshLfs);
  }

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  List<LfsFileInfo> _filesFor(List<LfsFileInfo> files, String pattern) => files
      .where((LfsFileInfo f) => lfsPatternMatches(f.path, pattern))
      .toList(growable: false);

  /// Matches the **pattern**, which is this list's row identity, and
  /// deliberately not the files the pattern claims.
  ///
  /// Filtering by claimed files would be a different feature («which pattern
  /// tracks `art/logo.psd`?»), and it is a *worse* fit for a box sitting over
  /// a list of patterns: it would show a row whose own text does not contain
  /// what was typed. The two readings agree on every query that appears in
  /// both, which is why the test pins the one that separates them.
  bool _matchesQuery(String pattern) {
    if (_query.trim().isEmpty) return true;
    return pattern.toLowerCase().contains(_query.trim().toLowerCase());
  }

  /// Rule 6's 「實際數量與耗時」, with **no 耗時 clause** -- this panel reads
  /// two lists in one refresh and measures nothing per row, so a duration
  /// here would be invented.
  String _statusLine({required int total, required int shown}) =>
      panelStatusLine(total: total, shown: shown, noun: 'pattern');

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<String> patterns = session.lfsPatterns;
    final List<LfsFileInfo> files = session.lfsFiles;
    final LfsInstallation? installation = session.lfsInstallation;
    final String? selected = patterns.contains(_selectedPattern)
        ? _selectedPattern
        : null;
    final List<String> visible = patterns
        .where(_matchesQuery)
        .toList(growable: false);

    return GbmPanelTabShell(
      storageId: 'panel.lfs',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a tracked pattern to see its files',
      toolbarSpec: PanelToolbarSpec(
        primary: <Widget>[
          GbmButton(
            label: _trackExpanded ? 'Cancel track' : 'Track…',
            kind: GbmButtonKind.primary,
            onPressed: () => setState(() => _trackExpanded = !_trackExpanded),
          ),
        ],
        maintenance: <Widget>[
          GbmButton(
            label: 'Fetch',
            kind: GbmButtonKind.ghost,
            onPressed: () => _session.fetchLfs(),
          ),
          GbmButton(
            label: 'Prune',
            kind: GbmButtonKind.ghost,
            onPressed: () => _session.pruneLfs(),
          ),
          GbmButton(
            label: 'Pull',
            kind: GbmButtonKind.ghost,
            onPressed: () => _session.pullLfs(),
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: (String value) => setState(() => _query = value),
        ),
      ),
      listHeader: PanelListHeaderText(
        text: 'Tracked patterns · ${visible.length}',
      ),
      statusBar: PanelStatusBarText(
        text: _statusLine(total: patterns.length, shown: visible.length),
      ),
      list: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_trackExpanded) _buildTrackForm(),
          Expanded(
            child: installation != null && !installation.available
                ? _NotInstalled(onInstall: _session.installLfs)
                : visible.isEmpty
                ? PanelEmptyList(
                    message: patterns.isEmpty
                        ? 'No tracked patterns'
                        : 'No pattern matches the filter',
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final String p = visible[i];
                      final int count = _filesFor(files, p).length;
                      return PanelListRow(
                        title: p,
                        subtitle: count == 1 ? '1 file' : '$count files',
                        selected: p == selected,
                        onTap: () => setState(() => _selectedPattern = p),
                      );
                    },
                  ),
          ),
        ],
      ),
      detail: selected == null
          ? const SizedBox.shrink()
          : _PatternFiles(files: _filesFor(files, selected)),
      detailActions: PanelDetailActions(
        dangerActions: <Widget>[
          GbmButton(
            label: 'Untrack',
            kind: GbmButtonKind.danger,
            onPressed: selected == null
                ? null
                : () {
                    _session.untrackLfsPattern(selected);
                    setState(() => _selectedPattern = null);
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildTrackForm() {
    return Padding(
      padding: const EdgeInsets.all(GbmSpacing.space3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _patternController,
              decoration: const InputDecoration(
                hintText: 'Pattern (e.g. *.psd)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _track(),
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(
            label: 'Track',
            kind: GbmButtonKind.primary,
            onPressed: _track,
          ),
        ],
      ),
    );
  }

  void _track() {
    final String pattern = _patternController.text.trim();
    if (pattern.isEmpty) return;
    _session.trackLfsPattern(pattern);
    setState(() {
      _trackExpanded = false;
      _patternController.clear();
    });
  }
}

/// P19 detail column: 對應檔案 + 本地快取狀態.
class _PatternFiles extends StatelessWidget {
  const _PatternFiles({required this.files});

  final List<LfsFileInfo> files;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    if (files.isEmpty) {
      return const PanelEmptyList(
        message: 'No tracked files match this pattern',
      );
    }
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, i) {
        final LfsFileInfo f = files[i];
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space4,
            vertical: GbmSpacing.space1,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  f.path,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              Text(
                // 本地快取狀態: a pointer file whose object is not cached
                // is the case that explains a "file looks wrong" report,
                // so it is the one that gets the non-default colour.
                f.downloadedLocally ? 'cached' : 'pointer only',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: f.downloadedLocally
                      ? colors.textTertiary
                      : colors.warning,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shown when `git lfs` is not installed: every action in this panel would
/// fail, so the state says why and offers the one thing that fixes it.
class _NotInstalled extends StatelessWidget {
  const _NotInstalled({required this.onInstall});

  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GbmSpacing.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Git LFS is not installed for this repository',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
            GbmButton(
              label: 'Install for this repository',
              kind: GbmButtonKind.primary,
              onPressed: onInstall,
            ),
          ],
        ),
      ),
    );
  }
}
