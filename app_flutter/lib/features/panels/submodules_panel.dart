import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/submodule_info.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/services/desktop_launcher.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_widgets.dart';

/// `manage-submodules` as a tab (spec page 14 `IAMAP`), on page 19's
/// template.
///
/// P19 `PANELSPEC` row:
/// - list: 路徑 + 目前 commit
/// - detail: URL、預期 vs 實際 commit、是否初始化
/// - toolbar: Init、Update、Sync、Open
///
/// **The toolbar carries two buttons beyond those four**, and that is a
/// deliberate deviation rather than an oversight: `gbm_submodule_add` and
/// `gbm_submodule_deinit` exist, work, and have **no entry point anywhere
/// in the spec** — not in `PANELSPEC`, not in `TOOLSMENU`, not in P04
/// `MENUS`. Dropping them to match the table exactly would orphan two
/// working capi calls and remove the only way to add a submodule at all.
/// Kept, separated after the four spec'd actions, and tracked as **#92** —
/// the same call Tier 6b made for the Cherry-pick button (#86) and for
/// `Create tag…` / `Undo last operation…` (#84/#85).
///
/// **Which of the six lands in which of rule 2's segments.** The rule names
/// its first segment 主要建立動作, and `Add…` is the only action here that
/// creates a submodule — so it is the primary one even though `PANELSPEC`
/// does not list it. `Init` reads like a creation and is not: it checks out
/// a submodule the superproject already records, and it is batch-shaped
/// (`paths:`) exactly like `Update` and `Sync`, so all three are 批次維護
/// 動作. `Open` leaves the panel, which is what 跳出去的動作 means.
/// `Deinit` deletes a checked-out working tree, so it goes to the detail
/// action row — the same 「拿不回來」 boundary that moves `Drop` and keeps
/// `Pop` on the stashes panel.
///
/// **預期 commit is absent.** [SubmoduleInfo] carries `headOid` (the
/// submodule's actual HEAD) but not the gitlink oid the superproject
/// records, and no capi reports it. What survives is `state`, which already
/// answers the question the comparison was for — `SubmoduleState.modified`
/// *means* the two differ. Absent rather than faked, the 待提交數 precedent.
class SubmodulesPanel extends ConsumerStatefulWidget {
  const SubmodulesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<SubmodulesPanel> createState() => _SubmodulesPanelState();
}

class _SubmodulesPanelState extends ConsumerState<SubmodulesPanel> {
  /// By path rather than index: `git submodule` output order is not
  /// guaranteed stable across refreshes.
  String? _selectedPath;
  String _query = '';
  bool _addExpanded = false;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_session.refreshSubmodules);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _pathController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  static String _describeState(SubmoduleState state) => switch (state) {
    SubmoduleState.notInitialized => 'not initialized',
    SubmoduleState.upToDate => 'up to date',
    SubmoduleState.modified => 'modified',
    SubmoduleState.conflicted => 'conflicted',
  };

  /// The URL is matched as well as the path: a vendored dependency is often
  /// remembered by where it came from rather than by where it was put.
  bool _matchesQuery(SubmoduleInfo submodule) {
    if (_query.trim().isEmpty) return true;
    final String needle = _query.trim().toLowerCase();
    return submodule.path.toLowerCase().contains(needle) ||
        submodule.name.toLowerCase().contains(needle) ||
        submodule.url.toLowerCase().contains(needle);
  }

  /// Rule 6's 「實際數量」. No 耗時 clause: the list arrives from one
  /// `git submodule status` and nothing here is timed per row -- printing a
  /// duration where nothing was measured decorates a count rather than
  /// reporting one.
  String _statusLine({required int total, required int shown}) =>
      panelStatusLine(total: total, shown: shown, noun: 'submodule');

  @override
  Widget build(BuildContext context) {
    final List<SubmoduleInfo> submodules = ref.watch(
      repoSessionProvider(widget.identity).select((s) => s.submodules),
    );
    final SubmoduleInfo? selected = submodules
        .where((SubmoduleInfo s) => s.path == _selectedPath)
        .firstOrNull;
    final List<SubmoduleInfo> visible = submodules
        .where(_matchesQuery)
        .toList();

    return GbmPanelTabShell(
      storageId: 'panel.submodules',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a submodule to see its details',
      toolbarSpec: PanelToolbarSpec(
        primary: <Widget>[
          GbmButton(
            label: _addExpanded ? 'Cancel add' : 'Add…',
            kind: GbmButtonKind.primary,
            onPressed: () => setState(() => _addExpanded = !_addExpanded),
          ),
        ],
        maintenance: <Widget>[
          // Init is a no-op on an already-initialized submodule, but
          // offering it only for uninitialized ones would make the button
          // flicker in and out; it is gated on selection alone, like Update
          // and Sync.
          GbmButton(
            label: 'Init',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () => _session.initSubmodules(paths: <String>[selected.path]),
          ),
          GbmButton(
            label: 'Update',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () => _session.updateSubmodules(
                    paths: <String>[selected.path],
                    init: true,
                  ),
          ),
          GbmButton(
            label: 'Sync',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () => _session.syncSubmodules(paths: <String>[selected.path]),
          ),
        ],
        external: <Widget>[
          // A submodule that was never initialized has no working tree to
          // open -- the directory exists but is empty.
          GbmButton(
            label: 'Open',
            kind: GbmButtonKind.ghost,
            onPressed:
                selected == null ||
                    selected.state == SubmoduleState.notInitialized
                ? null
                : () => ref
                      .read(desktopLauncherProvider)
                      .openInFileManager(
                        '${widget.identity.workDir}/${selected.path}',
                      ),
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: (String value) => setState(() => _query = value),
        ),
      ),
      detailActions: PanelDetailActions(
        dangerActions: <Widget>[
          GbmButton(
            label: 'Deinit',
            kind: GbmButtonKind.danger,
            onPressed: selected == null
                ? null
                : () {
                    _session.deinitSubmodules(paths: <String>[selected.path]);
                    setState(() => _selectedPath = null);
                  },
          ),
        ],
      ),
      listHeader: PanelListHeaderText(text: 'Submodules · ${visible.length}'),
      statusBar: PanelStatusBarText(
        text: _statusLine(total: submodules.length, shown: visible.length),
      ),
      list: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_addExpanded) _buildAddForm(),
          Expanded(
            child: visible.isEmpty
                ? PanelEmptyList(
                    message: submodules.isEmpty
                        ? 'No submodules'
                        : 'No submodule matches the filter',
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final SubmoduleInfo s = visible[i];
                      return PanelListRow(
                        title: s.path,
                        // An uninitialized submodule's headOid is not a
                        // commit anyone can look at, so say the state
                        // instead of showing a meaningless oid.
                        subtitle: s.state == SubmoduleState.notInitialized
                            ? _describeState(s.state)
                            : s.headOid,
                        selected: s.path == _selectedPath,
                        onTap: () => setState(() => _selectedPath = s.path),
                      );
                    },
                  ),
          ),
        ],
      ),
      detail: selected == null
          ? const SizedBox.shrink()
          : PanelDetailColumn(
              children: <Widget>[
                PanelDetailField(label: 'URL', value: selected.url, mono: true),
                PanelDetailField(
                  label: 'Current commit',
                  value: selected.headOid.isEmpty
                      ? 'None (not checked out)'
                      : selected.headOid,
                  mono: true,
                ),
                if (selected.branch.isNotEmpty)
                  PanelDetailField(label: 'Branch', value: selected.branch),
                PanelDetailField(
                  label: 'Initialized',
                  value: selected.state == SubmoduleState.notInitialized
                      ? 'No'
                      : 'Yes · ${_describeState(selected.state)}',
                ),
              ],
            ),
    );
  }

  Widget _buildAddForm() {
    return Padding(
      padding: const EdgeInsets.all(GbmSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: 'Repository URL',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              hintText: 'Path (leave empty to derive from URL)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          TextField(
            controller: _branchController,
            decoration: const InputDecoration(
              hintText: 'Branch (optional)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          Align(
            alignment: Alignment.centerRight,
            child: GbmButton(
              label: 'Add',
              kind: GbmButtonKind.primary,
              onPressed: () {
                final String url = _urlController.text.trim();
                if (url.isEmpty) return;
                _session.addSubmodule(
                  url,
                  path: _pathController.text.trim(),
                  branch: _branchController.text.trim(),
                );
                setState(() {
                  _addExpanded = false;
                  _urlController.clear();
                  _pathController.clear();
                  _branchController.clear();
                });
              },
            ),
          ),
          const Divider(height: GbmSpacing.space4 * 2),
        ],
      ),
    );
  }
}
