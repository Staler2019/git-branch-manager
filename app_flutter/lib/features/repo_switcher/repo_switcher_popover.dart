/// Spec page 02 item 15: "Sidebar 最上方一顆顯示目前 repo 的按鈕，點擊或按快捷鍵
/// 開彈窗。彈窗內是可搜尋的 repo 清單，每列顯示名稱與 ahead/behind，最近開啟的
/// 排前面；底部固定 Open / Clone 兩個入口。選定後彈窗關閉、整個視窗切到該 repo。
/// Esc 關閉不切換."
///
/// Deliberately a popover and not a modal dialog route -- the spec is
/// explicit about why ("彈窗而非 modal dialog：切 repo 不需要中斷式的確認，
/// Esc 關閉即回到原狀，不改變任何狀態"), which is also why this replaced the
/// `/dialogs/switch-repository` route that used to back Cmd/Ctrl+R.
///
/// ahead/behind per row is not rendered: `RepoRecord` (src/core/cache/
/// RepoIndexDb.h) stores only discovery metadata, and reading tracking
/// counts for a repository would mean opening a session per row -- left out
/// rather than faked.
library;

import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ffi/gbm_bindings.dart';
import '../../data/ffi/json_codec.dart';
import '../../data/models/git_error.dart';
import '../../data/models/repo_record.dart';
import '../../data/repositories/discovery_repository.dart';
import '../../data/repositories/gbm_bindings_provider.dart';
import '../../data/repositories/recents_repository.dart';
import '../../data/services/desktop_launcher.dart';
import '../../routing/app_router.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_menu.dart';
import '../../widgets/lucide_icon.dart';
import '../../widgets/prompt_text_dialog.dart';

/// Minimum popover width. The spec has the popover follow the sidebar's
/// width; below this the repository names stop being readable, so a narrow
/// sidebar widens the popover rather than truncating every row.
const double _kMinPopoverWidth = 240;

/// Lets a widget above [RepoSwitcherButton] open the popover -- the same
/// attach/external-trigger split `GbmSplitPaneController` uses, and for the
/// same reason: Cmd/Ctrl+R is registered by `WorkspaceScreen`, several
/// levels above the button whose rect the popover has to anchor to.
class RepoSwitcherController {
  _RepoSwitcherButtonState? _state;

  void _attach(_RepoSwitcherButtonState state) => _state = state;

  void _detach(_RepoSwitcherButtonState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  /// Opens the popover anchored under the button. No-op when no button is
  /// currently mounted (e.g. the sidebar is hidden).
  void open() => _state?.openPopover();
}

/// One row of the switcher list.
///
/// [isManual] marks the two sources spec page 11 keeps apart: entries that
/// came from a base-folder scan versus ones the user opened by hand ("列上會
/// 標示來源，手動加入的可單獨移除，掃描來的則要改 base folder 設定才會消失").
@immutable
class RepoSwitcherEntry {
  const RepoSwitcherEntry({
    required this.workDir,
    required this.name,
    required this.isManual,
    this.isMissing = false,
  });

  final String workDir;
  final String name;
  final bool isManual;
  final bool isMissing;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepoSwitcherEntry &&
          runtimeType == other.runtimeType &&
          workDir == other.workDir &&
          name == other.name &&
          isManual == other.isManual &&
          isMissing == other.isMissing;

  @override
  int get hashCode => Object.hash(workDir, name, isManual, isMissing);
}

/// Merges the two repository sources into the single list the popover shows
/// (spec page 11: "顯示的是兩種來源合併後的結果：base folders 掃到的，加上
/// 手動開啟過的").
///
/// Recently-opened repositories come first, newest-first, because that is
/// the spec's stated ordering for this list ("最近開啟的排前面"); everything
/// else follows sorted by name. A repository present in both sources is
/// listed once, from its recents position, and counts as scanned -- removing
/// it from the recents list would not make it disappear, so offering that is
/// what the spec warns against.
List<RepoSwitcherEntry> buildRepoSwitcherEntries({
  required List<RecentRepoEntry> recents,
  required List<RepoRecord> discovered,
}) {
  final Map<String, RepoRecord> byWorkDir = <String, RepoRecord>{
    for (final RepoRecord repo in discovered) repo.workDir: repo,
  };
  final Set<String> seen = <String>{};
  final List<RepoSwitcherEntry> entries = <RepoSwitcherEntry>[];

  for (final RecentRepoEntry recent in recents) {
    if (!seen.add(recent.workDir)) continue;
    final RepoRecord? record = byWorkDir[recent.workDir];
    entries.add(
      RepoSwitcherEntry(
        workDir: recent.workDir,
        name: record?.name ?? repoDisplayName(recent.workDir),
        isManual: record == null,
        isMissing: record?.isMissing ?? false,
      ),
    );
  }

  final List<RepoRecord> rest =
      discovered.where((RepoRecord r) => !seen.contains(r.workDir)).toList()
        ..sort((RepoRecord a, RepoRecord b) => a.name.compareTo(b.name));
  for (final RepoRecord repo in rest) {
    entries.add(
      RepoSwitcherEntry(
        workDir: repo.workDir,
        name: repo.name,
        isManual: false,
        isMissing: repo.isMissing,
      ),
    );
  }
  return entries;
}

/// Last path segment of [workDir], for entries with no discovery record to
/// take a name from. Trailing separators are ignored so `/home/me/proj/`
/// still reads as `proj`.
String repoDisplayName(String workDir) {
  final List<String> parts = workDir
      .split(RegExp(r'[/\\]'))
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? workDir : parts.last;
}

/// Substring match over name and path, case-insensitive -- the same shape as
/// the sidebar's branch filter (see `filterBranches`).
List<RepoSwitcherEntry> filterRepoSwitcherEntries(
  List<RepoSwitcherEntry> entries,
  String query,
) {
  final String needle = query.trim().toLowerCase();
  if (needle.isEmpty) return entries;
  return entries
      .where(
        (RepoSwitcherEntry e) =>
            e.name.toLowerCase().contains(needle) ||
            e.workDir.toLowerCase().contains(needle),
      )
      .toList(growable: false);
}

/// Asks for a working-directory path and switches the window to it, then
/// dismisses [onDismiss]'s surface (the switcher popover, when called from
/// its footer).
///
/// Deliberately a path prompt and not a native folder picker: this app has
/// no file-dialog plugin wired up (the same M1 limitation the base-folder
/// field in Preferences carries). Prompting *before* dismissing means Esc on
/// the prompt leaves the switcher exactly as it was, which is what "Esc 關閉
/// 不切換" asks for.
///
/// Backs both the popover footer's `Open repository…` and File → Open
/// repository… / Add local repository… (see `workspace_screen.dart`); the
/// opened path lands in the manually-opened list via `RecentsRepository`
/// when its session opens.
Future<void> promptOpenRepository(
  BuildContext context, {
  VoidCallback? onDismiss,
}) async {
  final GoRouter router = GoRouter.of(context);
  final String? path = await promptText(
    context,
    title: 'Open Repository',
    label: 'Path to the working directory',
  );
  if (path == null) return;
  onDismiss?.call();
  router.go(RoutePaths.workspaceFor(repoIdFor(path)));
}

/// Runs `git init` on a path the user provides (via `gbm_repo_init()`), then
/// opens it exactly like [promptOpenRepository] does -- a fresh repository
/// has no session of its own to open until it exists on disk. Backs File →
/// New repository…
///
/// Needs [ref] (unlike [promptOpenRepository]) because init runs before any
/// session exists: there is no `RepoSessionController` yet to dispatch
/// through, so this reaches `gbm_repo_init()` directly via
/// `gbmBindingsProvider`.
Future<void> promptNewRepository(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onDismiss,
}) async {
  final GoRouter router = GoRouter.of(context);
  final String? path = await promptText(
    context,
    title: 'New Repository',
    label: 'Path for the new repository',
  );
  if (path == null) return;

  final GbmBindings bindings = ref.read(gbmBindingsProvider);
  final Pointer<Utf8> pathPtr = path.toNativeUtf8();
  final int result;
  try {
    result = bindings.repoInit(pathPtr);
  } finally {
    malloc.free(pathPtr);
  }
  if (result != 0) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(_decodeInitCloneErrorMessage(bindings))),
      );
    }
    return;
  }

  onDismiss?.call();
  router.go(RoutePaths.workspaceFor(repoIdFor(path)));
}

/// Runs `git clone <url> <destPath>` (via `gbm_repo_clone()`), then opens
/// the result exactly like [promptOpenRepository] does. Backs both the
/// switcher popover footer's `Clone repository…` and File → Clone
/// repository….
///
/// Two fields (unlike New/Open's single path) need their own small dialog
/// rather than [promptText] -- see `_promptClone` below, which follows
/// `manage_remotes_dialog.dart`'s `_promptAddRemote()` pattern.
Future<void> promptCloneRepository(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onDismiss,
}) async {
  final GoRouter router = GoRouter.of(context);
  final ({String url, String destPath})? input = await _promptClone(context);
  if (input == null) return;

  final GbmBindings bindings = ref.read(gbmBindingsProvider);
  final Pointer<Utf8> urlPtr = input.url.toNativeUtf8();
  final Pointer<Utf8> destPtr = input.destPath.toNativeUtf8();
  final int result;
  try {
    result = bindings.repoClone(urlPtr, destPtr);
  } finally {
    malloc.free(urlPtr);
    malloc.free(destPtr);
  }
  if (result != 0) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(_decodeInitCloneErrorMessage(bindings))),
      );
    }
    return;
  }

  onDismiss?.call();
  router.go(RoutePaths.workspaceFor(repoIdFor(input.destPath)));
}

String _decodeInitCloneErrorMessage(GbmBindings bindings) {
  final String json = readLastResultJson(bindings);
  if (json.isEmpty) return 'The operation failed.';
  return GitError.fromJson(jsonDecode(json) as Map<String, dynamic>).message;
}

Future<({String url, String destPath})?> _promptClone(BuildContext context) {
  final TextEditingController urlController = TextEditingController();
  final TextEditingController destController = TextEditingController();
  return showDialog<({String url, String destPath})>(
    context: context,
    builder: (dialogContext) {
      final GbmColors colors = dialogContext.gbmColors;
      ({String url, String destPath})? resultFromControllers() {
        final String url = urlController.text.trim();
        final String destPath = destController.text.trim();
        return url.isEmpty || destPath.isEmpty
            ? null
            : (url: url, destPath: destPath);
      }

      // Same "only pop on a valid result" discipline as
      // manage_remotes_dialog.dart's _promptAddRemote(): a required field
      // left empty keeps the dialog open with what was already typed,
      // rather than silently discarding it.
      void submitIfValid() {
        final ({String url, String destPath})? result = resultFromControllers();
        if (result != null) {
          Navigator.of(dialogContext).pop(result);
        }
      }

      return AlertDialog(
        title: const Text('Clone Repository'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: urlController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Repository URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            TextField(
              controller: destController,
              decoration: const InputDecoration(
                labelText: 'Destination path',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => submitIfValid(),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(onPressed: submitIfValid, child: const Text('Clone')),
        ],
      );
    },
  );
}

/// The sidebar's top row: which repository this window is showing, and the
/// way to change it.
class RepoSwitcherButton extends StatefulWidget {
  const RepoSwitcherButton({
    super.key,
    required this.currentWorkDir,
    this.controller,
  });

  final String currentWorkDir;

  /// Optional external trigger for Cmd/Ctrl+R -- see [RepoSwitcherController].
  final RepoSwitcherController? controller;

  @override
  State<RepoSwitcherButton> createState() => _RepoSwitcherButtonState();
}

class _RepoSwitcherButtonState extends State<RepoSwitcherButton> {
  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(RepoSwitcherButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  /// Anchors the popover to this button's own rect, so it opens flush under
  /// the button at the sidebar's current width ("貼齊 sidebar 頂端按鈕下緣
  /// 展開，寬度跟隨 sidebar").
  void openPopover() {
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final Offset topLeft = box.localToGlobal(Offset.zero);
    showRepoSwitcherPopover(
      context,
      anchor: topLeft & box.size,
      currentWorkDir: widget.currentWorkDir,
    );
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GbmSpacing.space3,
        GbmSpacing.space3,
        GbmSpacing.space3,
        0,
      ),
      child: Tooltip(
        message: widget.currentWorkDir,
        child: InkWell(
          onTap: openPopover,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
            decoration: BoxDecoration(
              color: colors.surfacePanelRaised,
              border: Border.all(color: colors.borderDefault),
              borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
            ),
            child: Row(
              children: <Widget>[
                LucideIcon('git-fork', size: 14, color: colors.textSecondary),
                const SizedBox(width: GbmSpacing.space2),
                Expanded(
                  child: Text(
                    repoDisplayName(widget.currentWorkDir),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      fontWeight: GbmTypography.weightSemibold,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 16, color: colors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the switcher under [anchor] (a global-coordinate rect, normally the
/// sidebar button's).
///
/// `showGeneralDialog` rather than `showGbmMenu`: that helper wraps its panel
/// in a *disabled* `PopupMenuItem`, which is fine for the plain rows menus
/// are made of but would swallow every gesture the search field here needs.
/// The transparent barrier keeps the click-outside-and-Esc dismissal the
/// spec asks for without dimming the window behind it.
Future<void> showRepoSwitcherPopover(
  BuildContext context, {
  required Rect anchor,
  String? currentWorkDir,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    pageBuilder: (BuildContext dialogContext, _, _) =>
        _RepoSwitcherPopover(anchor: anchor, currentWorkDir: currentWorkDir),
  );
}

class _RepoSwitcherPopover extends StatelessWidget {
  const _RepoSwitcherPopover({required this.anchor, this.currentWorkDir});

  final Rect anchor;
  final String? currentWorkDir;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Size screen = MediaQuery.sizeOf(context);
    final double width = math.max(anchor.width, _kMinPopoverWidth);
    // Clamped so a sidebar button near either screen edge -- or a popover
    // wider than the sidebar that spawned it -- still lands fully on screen.
    final double left = math.max(
      GbmSpacing.space2,
      math.min(anchor.left, screen.width - width - GbmSpacing.space2),
    );
    final double top = anchor.bottom + GbmSpacing.space1;
    final double maxHeight = math.max(
      120,
      screen.height - top - GbmSpacing.space3,
    );

    return Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Container(
                padding: const EdgeInsets.all(GbmSpacing.space1),
                decoration: BoxDecoration(
                  color: colors.surfaceOverlay,
                  border: Border.all(color: colors.borderDefault),
                  borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
                  boxShadow: GbmEffects.shadowLg(context.gbmThemeVariant),
                ),
                child: RepoSwitcherList(
                  currentWorkDir: currentWorkDir,
                  autofocusSearch: true,
                  onDismiss: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The switcher's contents, without any popover chrome: a search field, the
/// merged repository list, and the fixed Open / Clone footer.
///
/// Split out from [showRepoSwitcherPopover] because the welcome screen shows
/// the same list inline -- with no repository open there is no sidebar to
/// hang a popover off, but it is still the same list of the same two
/// sources, with the same row context menu.
class RepoSwitcherList extends ConsumerStatefulWidget {
  const RepoSwitcherList({
    super.key,
    this.currentWorkDir,
    this.onDismiss,
    this.autofocusSearch = false,
  });

  /// Highlighted as the repository this window is already showing.
  final String? currentWorkDir;

  /// Closes the surface this list is embedded in before navigating. Null
  /// when the list is not in a popover (the welcome screen), where popping
  /// would take the underlying screen with it.
  final VoidCallback? onDismiss;

  final bool autofocusSearch;

  @override
  ConsumerState<RepoSwitcherList> createState() => _RepoSwitcherListState();
}

class _RepoSwitcherListState extends ConsumerState<RepoSwitcherList> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Dismisses first, then navigates: a popover opened with
  /// `showGeneralDialog` is an imperative route on the root navigator, so
  /// `go()` alone would rebuild the page stack underneath and leave the
  /// popover floating on top of the repository it just switched to.
  void _switchTo(String workDir) {
    final GoRouter router = GoRouter.of(context);
    widget.onDismiss?.call();
    router.go(RoutePaths.workspaceFor(repoIdFor(workDir)));
  }

  Future<void> _removeFromList(RepoSwitcherEntry entry) async {
    await ref.read(recentsRepositoryProvider).remove(entry.workDir);
    // RecentsRepository is a plain Provider over SharedPreferences with no
    // notifier of its own, so setState is what re-runs the read() below.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<RecentRepoEntry> recents = ref
        .watch(recentsRepositoryProvider)
        .read();
    final DiscoveryState discovery = ref.watch(discoveryProvider);
    final List<RepoSwitcherEntry> entries = filterRepoSwitcherEntries(
      buildRepoSwitcherEntries(recents: recents, discovered: discovery.repos),
      _query,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GbmSpacing.space1,
            GbmSpacing.space1,
            GbmSpacing.space1,
            GbmSpacing.space2,
          ),
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: _searchController,
              autofocus: widget.autofocusSearch,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
              onChanged: (String value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search repositories',
                hintStyle: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textTertiary,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(GbmSpacing.space2),
                  child: LucideIcon(
                    'search',
                    size: 13,
                    color: colors.textTertiary,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: GbmSpacing.space2,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
              ),
            ),
          ),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GbmSpacing.space2,
              vertical: GbmSpacing.space3,
            ),
            child: Text(
              _query.trim().isEmpty
                  ? 'No repositories yet. Add a base folder in '
                        'Preferences → Repository sources, or use Open '
                        'repository… below.'
                  : 'No repository matches “$_query”.',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textTertiary,
              ),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              itemBuilder: (BuildContext context, int index) {
                final RepoSwitcherEntry entry = entries[index];
                return RepoSwitcherRow(
                  entry: entry,
                  isCurrent: entry.workDir == widget.currentWorkDir,
                  onTap: () => _switchTo(entry.workDir),
                  onOpenInFileManager: () => ref
                      .read(desktopLauncherProvider)
                      .openInFileManager(entry.workDir),
                  onOpenInTerminal: () => ref
                      .read(desktopLauncherProvider)
                      .openTerminal(entry.workDir),
                  onRemoveFromList: entry.isManual
                      ? () => _removeFromList(entry)
                      : null,
                );
              },
            ),
          ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space1,
            vertical: GbmSpacing.space1,
          ),
          color: colors.borderSubtle,
        ),
        _FooterAction(
          label: 'Open repository…',
          shortcut: _shortcutLabel('O'),
          onTap: () =>
              promptOpenRepository(context, onDismiss: widget.onDismiss),
        ),
        _FooterAction(
          label: 'Clone repository…',
          shortcut: _shortcutLabel('Shift+N'),
          onTap: () =>
              promptCloneRepository(context, ref, onDismiss: widget.onDismiss),
        ),
      ],
    );
  }

  String _shortcutLabel(String key) =>
      Theme.of(context).platform == TargetPlatform.macOS
      ? '⌘$key'
      : 'Ctrl+$key';
}

/// One repository row, with the 05-A context menu on right-click ("右鍵切換
/// 彈窗內的 repository 列").
///
/// Presentational: every action arrives as a callback so the row stays
/// widget-testable against a bare `GoRouter` with no `ProviderScope`, the
/// same split `MenuBarRow`/`TopBar`/`TabRow` follow.
class RepoSwitcherRow extends StatelessWidget {
  const RepoSwitcherRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.isCurrent = false,
    this.onOpenInFileManager,
    this.onOpenInTerminal,
    this.onRemoveFromList,
  });

  final RepoSwitcherEntry entry;
  final VoidCallback onTap;
  final bool isCurrent;
  final VoidCallback? onOpenInFileManager;
  final VoidCallback? onOpenInTerminal;

  /// Null renders "Remove from list" disabled -- which is the correct state
  /// for a scanned repository, since forgetting it here would only have it
  /// reappear on the next scan (spec page 11: "掃描來的則要改 base folder
  /// 設定才會消失——避免使用者刪了卻在下次掃描又冒出來").
  final VoidCallback? onRemoveFromList;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Semantics(
      button: true,
      selected: isCurrent,
      label: entry.isMissing
          ? '${entry.name}, ${entry.workDir}, missing'
          : '${entry.name}, ${entry.workDir}',
      child: GestureDetector(
        onSecondaryTapDown: (TapDownDetails details) =>
            _openContextMenu(context, details),
        child: Tooltip(
          message: entry.workDir,
          waitDuration: const Duration(milliseconds: 600),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
            child: Container(
              height: GbmSpacing.rowHeightCompact,
              padding: const EdgeInsets.symmetric(
                horizontal: GbmSpacing.space2,
              ),
              decoration: BoxDecoration(
                color: isCurrent ? colors.surfaceSelected : null,
                borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
              ),
              child: Row(
                children: <Widget>[
                  LucideIcon(
                    'git-fork',
                    size: 13,
                    color: isCurrent ? colors.accent : colors.textSecondary,
                  ),
                  const SizedBox(width: GbmSpacing.space2),
                  Expanded(
                    child: Text(
                      entry.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        fontWeight: isCurrent
                            ? GbmTypography.weightSemibold
                            : GbmTypography.weightRegular,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (entry.isMissing)
                    Text(
                      'offline',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.danger,
                      ),
                    )
                  else if (entry.isManual)
                    // Spec page 11: rows say which source they came from, so
                    // it is obvious why only some of them can be removed
                    // here.
                    Text(
                      'manual',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 05-A, trimmed to the entries that have something behind them here:
  /// fetch/pull/push act on an open session, which a repository in this list
  /// does not have until it is switched to.
  void _openContextMenu(BuildContext context, TapDownDetails details) {
    showGbmContextMenu(context, details.globalPosition, <GbmMenuItem>[
      GbmMenuItem(
        label: 'Open',
        icon: Icons.folder_open_outlined,
        onTap: onTap,
      ),
      GbmMenuItem(
        label: 'Open in file manager',
        icon: Icons.folder_outlined,
        onTap: onOpenInFileManager,
      ),
      GbmMenuItem(
        label: 'Open in terminal',
        icon: Icons.terminal_outlined,
        onTap: onOpenInTerminal,
      ),
      GbmMenuItem(
        label: 'Settings…',
        icon: Icons.settings_outlined,
        onTap: () => context.push(
          RoutePaths.repositorySettingsDialogFor(
            Uri.encodeComponent(entry.workDir),
          ),
        ),
      ),
      const GbmMenuItem.separator(),
      GbmMenuItem(
        label: 'Remove from list',
        icon: Icons.delete_outline,
        danger: true,
        onTap: onRemoveFromList,
      ),
    ]);
  }
}

class _FooterAction extends StatefulWidget {
  const _FooterAction({
    required this.label,
    required this.shortcut,
    required this.onTap,
  });

  final String label;
  final String shortcut;
  final VoidCallback? onTap;

  @override
  State<_FooterAction> createState() => _FooterActionState();
}

class _FooterActionState extends State<_FooterAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool enabled = widget.onTap != null;
    final Color foreground = !enabled
        ? colors.textTertiary
        : (_hovered ? colors.textOnAccent : colors.textPrimary);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = enabled),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space2,
            vertical: GbmSpacing.space2,
          ),
          decoration: BoxDecoration(
            color: _hovered ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: foreground,
                  ),
                ),
              ),
              Text(
                widget.shortcut,
                style: TextStyle(
                  fontFamily: GbmTypography.fontMono,
                  fontSize: 10.5,
                  color: _hovered
                      ? foreground.withValues(alpha: 0.8)
                      : colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
