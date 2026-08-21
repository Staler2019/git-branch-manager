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
/// Add…/Deinit, tracked on #76.
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

    return GbmPanelTabShell(
      storageId: 'panel.lfs',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a tracked pattern to see its files',
      toolbar: <Widget>[
        GbmButton(
          label: _trackExpanded ? 'Cancel track' : 'Track…',
          onPressed: () => setState(() => _trackExpanded = !_trackExpanded),
        ),
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
        GbmButton(label: 'Fetch', onPressed: () => _session.fetchLfs()),
        GbmButton(label: 'Prune', onPressed: () => _session.pruneLfs()),
        GbmButton(label: 'Pull', onPressed: () => _session.pullLfs()),
      ],
      list: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_trackExpanded) _buildTrackForm(),
          Expanded(
            child: installation != null && !installation.available
                ? _NotInstalled(onInstall: _session.installLfs)
                : patterns.isEmpty
                ? const PanelEmptyList(message: 'No tracked patterns')
                : ListView.builder(
                    itemCount: patterns.length,
                    itemBuilder: (context, i) {
                      final String p = patterns[i];
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
