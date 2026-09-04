import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../actions/gbm_menu_model.dart';
import '../../../actions/gbm_shortcuts.dart';
import '../../../data/models/base_folder_record.dart';
import '../../../data/repositories/app_preferences_repository.dart';
import '../../../data/repositories/discovery_repository.dart';
import '../../../data/repositories/recents_repository.dart';
import '../../../data/services/file_save_picker.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/theme_mode_provider.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/theme_switcher_buttons.dart';
import '../../update/auto_update_check.dart';

/// The six sections of spec page 11's `PREFNAV`, in the spec's own order.
enum PreferencesSection {
  general,
  repositorySources,
  git,
  appearance,
  shortcuts,
  advanced,
}

/// File → Preferences… (Ctrl/Cmd+,).
///
/// Spec page 11: "六段：General / Repository sources / Git / Appearance /
/// Shortcuts / Advanced。這裡全部是應用層級設定，單一 repo 的設定在
/// Repository → Settings…（見 06）."
///
/// Application-scoped and therefore routed at `/dialogs/preferences`, not
/// under `/repo/:repoId/` -- it opens with no repository at all, from the
/// repo list as well as from a workspace. What used to live here (per-repo
/// Git identity and commit-graph) has moved to
/// `repository_settings_dialog.dart`, which is where the spec puts it.
class PreferencesDialogContent extends ConsumerStatefulWidget {
  const PreferencesDialogContent({super.key});

  @override
  ConsumerState<PreferencesDialogContent> createState() =>
      _PreferencesDialogContentState();
}

class _PreferencesDialogContentState
    extends ConsumerState<PreferencesDialogContent> {
  PreferencesSection _section = PreferencesSection.general;

  // Section names stay English -- `PREFNAV`'s own six names are these exact
  // English words (G1i; spec-auditor confirmed the app already matches).
  static String label(PreferencesSection section) => switch (section) {
    PreferencesSection.general => 'General',
    PreferencesSection.repositorySources => 'Repository sources',
    PreferencesSection.git => 'Git',
    PreferencesSection.appearance => 'Appearance',
    PreferencesSection.shortcuts => 'Shortcuts',
    PreferencesSection.advanced => 'Advanced',
  };

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return GbmDialogShell(
      title: 'Preferences',
      width: 720,
      actions: <Widget>[
        GbmButton(
          label: 'Close',
          kind: GbmButtonKind.primary,
          onPressed: () => context.pop(),
        ),
      ],
      child: SizedBox(
        height: 420,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Left nav -- spec page 11 item 1.
            SizedBox(
              width: 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final PreferencesSection section
                      in PreferencesSection.values)
                    _NavItem(
                      label: label(section),
                      selected: section == _section,
                      onTap: () => setState(() => _section = section),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: colors.borderSubtle),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: GbmSpacing.space4),
                child: SingleChildScrollView(
                  child: switch (_section) {
                    PreferencesSection.general => const _GeneralSection(),
                    PreferencesSection.repositorySources =>
                      const _RepositorySourcesSection(),
                    PreferencesSection.git => const _GitSection(),
                    PreferencesSection.appearance => const _AppearanceSection(),
                    PreferencesSection.shortcuts => const _ShortcutsSection(),
                    PreferencesSection.advanced => const _AdvancedSection(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space2,
            vertical: GbmSpacing.space2,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.surfaceSelected : null,
            borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              fontWeight: selected
                  ? GbmTypography.weightSemibold
                  : GbmTypography.weightRegular,
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GbmSpacing.space2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: GbmTypography.textXs,
          fontWeight: GbmTypography.weightSemibold,
          color: context.gbmColors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A checkbox row with an explanatory subtitle -- the shape almost every
/// setting on this dialog takes.
class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return CheckboxListTile(
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        title,
        style: TextStyle(
          fontSize: GbmTypography.textSm,
          color: colors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: GbmTypography.textXs,
          color: colors.textTertiary,
          height: GbmTypography.leadingNormal,
        ),
      ),
      onChanged: (bool? v) => onChanged(v ?? false),
    );
  }
}

/// A small integer field (minutes, day counts, row limits).
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final int value;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.suffix.isEmpty ? null : widget.suffix,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        // Only a parseable positive value is committed -- a half-typed field
        // must not momentarily persist 0 and change behaviour mid-keystroke.
        onChanged: (String text) {
          final int? parsed = int.tryParse(text.trim());
          if (parsed != null && parsed > 0) widget.onChanged(parsed);
        },
      ),
    );
  }
}

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPreferences prefs = ref.watch(appPreferencesProvider);
    final AppPreferencesNotifier notifier = ref.read(
      appPreferencesProvider.notifier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('自動 FETCH'),
        // G1i: `[DRIFT-auto-fetch-unwired]` records that `autoFetchEnabled`/
        // `autoFetchMinutes` are stored and drawn but read by no timer --
        // this copy is worded to match that, not spec P11 item 9's prose
        // (which describes the feature as if it already runs).
        _SettingSwitch(
          title: '在背景 fetch 目前開啟的 repository',
          subtitle:
              '純 fetch，不會動到 working tree，只抓目前開啟的這一個 '
              'repository。目前這個開關只會把設定存起來——還沒有背景排程真的 '
              '照著它去執行 fetch。',
          value: prefs.autoFetchEnabled,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(autoFetchEnabled: v),
          ),
        ),
        if (prefs.autoFetchEnabled) ...<Widget>[
          const SizedBox(height: GbmSpacing.space2),
          _NumberField(
            label: '每隔',
            suffix: '分鐘',
            value: prefs.autoFetchMinutes,
            onChanged: (int v) => notifier.update(
              (AppPreferences p) => p.copyWith(autoFetchMinutes: v),
            ),
          ),
        ],
        const SizedBox(height: GbmSpacing.space2),
        Text(
          '之後接上背景排程後，fetch 失敗不會跳出對話框——結果只會反映在 '
          'ahead/behind 數字、gone 標記和記錄裡。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: context.gbmColors.textTertiary,
            height: GbmTypography.leadingNormal,
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('開啟 REPOSITORY'),
        _SettingSwitch(
          title: '記住手動開啟的 repository',
          subtitle:
              '用 Open repository… 開啟的 repository 會另外記在自己的清單，跟 '
              '掃描到的基礎資料夾分開——臨時開一次的專案不需要因此更動掃描 '
              '設定。',
          value: prefs.recordManualOpens,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(recordManualOpens: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        // Not from the spec -- the 21-page design predates the update
        // feature. Placed in General beside the other two background
        // activities (automatic fetch, scanning) for the same reason they
        // are here: things the app does on its own without being asked.
        const _SectionHeading('更新'),
        _SettingSwitch(
          title: '啟動時檢查更新',
          subtitle:
              '啟動後幾秒會問一次 GitHub，一天最多一次。沒有新版本、或檢查 '
              '失敗都不會顯示任何東西。關閉這個開關會完全停止這個請求；'
              'Help → Check for updates… 仍然可以用。',
          value: prefs.autoUpdateCheckEnabled,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(autoUpdateCheckEnabled: v),
          ),
        ),
        // Read-only status, not a setting -- `update.lastAutoCheck` is
        // state, and this row neither edits nor offers to reset it. It is
        // here for the same reason the skipped-version row below is: without
        // it, "the startup check found nothing" and "the startup check is
        // not due for another 23 hours" look identical from the outside,
        // which is how a working automatic check reads as a broken one.
        //
        // Read rather than watched: the stamp is written once, a few seconds
        // after launch, and this dialog is normally opened long after that.
        // A check that lands while Preferences is already open leaves the
        // line one reopen behind, which is cheaper than rebuilding the whole
        // section off a store that publishes nothing.
        const SizedBox(height: GbmSpacing.space2),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                lastAutoCheckLabel(
                  ref
                      .read(sharedPreferencesProvider)
                      .getString(kLastAutoUpdateCheckKey),
                ),
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: context.gbmColors.textTertiary,
                  height: GbmTypography.leadingNormal,
                ),
              ),
            ),
            const SizedBox(width: GbmSpacing.space2),
            // Routed rather than a callback, so it reaches the same dialog
            // About's button does with no repository open. Replacement, not
            // a push: leaving Preferences stacked underneath is not what
            // "now" means -- and the update dialog runs a fresh check on
            // mount, so this really is a check rather than a replay.
            GbmButton(
              label: 'Check for updates now',
              kind: GbmButtonKind.secondary,
              onPressed: () => context.pushReplacement(RoutePaths.updateDialog),
            ),
          ],
        ),
        // Only rendered while something is actually skipped. A suppression
        // the user can neither see nor undo is hidden material state.
        if (prefs.skippedVersion.isNotEmpty) ...<Widget>[
          const SizedBox(height: GbmSpacing.space2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '啟動檢查目前跳過版本 ${prefs.skippedVersion}。'
                  'Help → Check for updates… 仍然會回報這個版本。',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: context.gbmColors.textTertiary,
                    height: GbmTypography.leadingNormal,
                  ),
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              GbmButton(
                label: 'Stop skipping',
                kind: GbmButtonKind.secondary,
                onPressed: () => notifier.update(
                  (AppPreferences p) => p.copyWith(skippedVersion: ''),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RepositorySourcesSection extends ConsumerStatefulWidget {
  const _RepositorySourcesSection();

  @override
  ConsumerState<_RepositorySourcesSection> createState() =>
      _RepositorySourcesSectionState();
}

class _RepositorySourcesSectionState
    extends ConsumerState<_RepositorySourcesSection> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  /// Spec page 11 item 3's "Add folder…". Typing a path by hand still
  /// works -- [_browse] below fills the same field rather than replacing it.
  void _addAndScan() {
    final String path = _pathController.text.trim();
    if (path.isEmpty) return;
    ref.read(discoveryProvider.notifier).addBaseFolderAndScan(path);
    _pathController.clear();
  }

  /// D5: the native folder picker `file_selector` already brought in for
  /// 05-K's "Save this revision as…" and the patches/changed-files panels
  /// ([FileSavePicker]) -- this field predates that dependency and was left
  /// as a plain path text box, which is the same gap [_pathController]'s
  /// counterpart in the Add-worktree dialog had.
  Future<void> _browse() async {
    final String? dir = await ref.read(fileSavePickerProvider).pickDirectory();
    if (dir == null || !mounted) return;
    setState(() => _pathController.text = dir);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final AppPreferences prefs = ref.watch(appPreferencesProvider);
    final AppPreferencesNotifier notifier = ref.read(
      appPreferencesProvider.notifier,
    );
    final DiscoveryState discovery = ref.watch(discoveryProvider);
    final List<RecentRepoEntry> recents = ref
        .watch(recentsRepositoryProvider)
        .read();

    // Spec page 11 item 5: "永遠顯示實際數字" -- repo count, folder count,
    // and the slowest observed scan, all read off the records rather than
    // rounded or summarised away.
    final int enabledFolders = discovery.baseFolders
        .where((BaseFolderRecord f) => f.enabled)
        .length;
    final int slowestScanMs = discovery.baseFolders.fold<int>(
      0,
      (int acc, BaseFolderRecord f) => f.lastScanMs > acc ? f.lastScanMs : acc,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('基礎資料夾'),
        if (discovery.baseFolders.isEmpty)
          Text(
            '目前沒有基礎資料夾。在下面新增一個，底下所有內容都會被掃描來尋找 '
            'repository。',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textTertiary,
            ),
          )
        else
          for (final BaseFolderRecord folder in discovery.baseFolders)
            _BaseFolderRow(folder: folder),
        const SizedBox(height: GbmSpacing.space2),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _pathController,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: '要掃描的資料夾，例如 /home/you/code',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addAndScan(),
              ),
            ),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(
              label: '瀏覽…',
              kind: GbmButtonKind.secondary,
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: _browse,
            ),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(
              label: 'Add folder…',
              kind: GbmButtonKind.primary,
              onPressed: discovery.isScanning ? null : _addAndScan,
            ),
          ],
        ),
        const SizedBox(height: GbmSpacing.space2),
        Text(
          '${discovery.repos.length} 個 repository，來自 $enabledFolders 個'
          '已啟用的資料夾'
          '${slowestScanMs > 0 ? '，最慢一次掃描花了 ${slowestScanMs}ms' : ''}。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        GbmButton(
          label: discovery.isScanning ? 'Scanning…' : 'Rescan now',
          onPressed: discovery.isScanning
              ? null
              : () => ref.read(discoveryProvider.notifier).rescan(),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('自動掃描'),
        _SettingSwitch(
          title: '在背景重新掃描基礎資料夾',
          subtitle:
              '低優先度工作——只會併入狀態列的工作數量，不會另外顯示。關閉時，'
              '只有按 Rescan now 才會掃描。',
          value: prefs.autoScanEnabled,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(autoScanEnabled: v),
          ),
        ),
        if (prefs.autoScanEnabled) ...<Widget>[
          const SizedBox(height: GbmSpacing.space2),
          _NumberField(
            label: '每隔',
            suffix: '分鐘',
            value: prefs.autoScanMinutes,
            onChanged: (int v) => notifier.update(
              (AppPreferences p) => p.copyWith(autoScanMinutes: v),
            ),
          ),
        ],
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('手動加入'),
        if (recents.isEmpty)
          Text(
            '目前沒有記錄。',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          )
        else
          for (final RecentRepoEntry entry in recents)
            _RecentEntryRow(
              entry: entry,
              // Same non-notifier refresh pattern as Clear list below --
              // RecentsRepository has no state of its own to watch.
              onRemove: () async {
                await ref.read(recentsRepositoryProvider).remove(entry.workDir);
                if (mounted) setState(() {});
              },
            ),
        const SizedBox(height: GbmSpacing.space1),
        Text(
          '清空這份清單只是忘記這些項目——磁碟上的東西不會被刪除。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        GbmButton(
          label: 'Clear list',
          onPressed: recents.isEmpty
              ? null
              // RecentsRepository is a plain Provider over SharedPreferences
              // with no notifier of its own, so nothing rebuilds on its own
              // after a write -- setState is what re-runs the read() above.
              : () async {
                  await ref.read(recentsRepositoryProvider).clear();
                  if (mounted) setState(() {});
                },
        ),
      ],
    );
  }
}

/// One recorded manual open, with its own delete affordance -- spec page 11
/// item 7's "手動加入的可單獨移除" (a manually-opened entry can be removed on
/// its own, separate from the batch "Clear list" below).
class _RecentEntryRow extends StatelessWidget {
  const _RecentEntryRow({required this.entry, required this.onRemove});

  final RecentRepoEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              entry.workDir,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: ValueKey<String>('recent-entry-remove-${entry.workDir}'),
            icon: Icon(Icons.close, size: 16, color: colors.textTertiary),
            tooltip: '從清單移除',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _BaseFolderRow extends ConsumerWidget {
  const _BaseFolderRow({required this.folder});

  final BaseFolderRecord folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    // A pure local filesystem check -- no capi call, no persisted state.
    // Re-evaluated on every rebuild, so it never goes stale the way a
    // one-time-at-scan-time flag would if the folder disappeared afterwards.
    // Settings are kept either way (see the class doc comment on
    // DiscoveryController): this is a visual marker only, never a block.
    final bool isOffline = !Directory(folder.path).existsSync();

    final String scanSummary =
        'depth ${folder.maxDepth} · 掃描了 ${folder.lastScanDirs} 個目錄'
        '${folder.lastScanSkipped > 0 ? '，略過 ${folder.lastScanSkipped} 個（超過 depth 限制）' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: GbmSpacing.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Checkbox(
            value: folder.enabled,
            visualDensity: VisualDensity.compact,
            onChanged: (bool? value) => ref
                .read(discoveryProvider.notifier)
                .setBaseFolderEnabled(folder.id, value ?? true),
          ),
          if (isOffline) ...<Widget>[
            Tooltip(
              message:
                  '這個資料夾目前無法連線——設定會保留，不會自動移除任何 '
                  '東西。',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: colors.warning,
              ),
            ),
            const SizedBox(width: GbmSpacing.space1),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  folder.path,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  scanSummary,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          _DepthField(
            value: folder.maxDepth,
            onChanged: (int depth) => ref
                .read(discoveryProvider.notifier)
                .setBaseFolderDepth(folder.id, depth),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: colors.danger),
            tooltip: '移除',
            onPressed: () => ref
                .read(discoveryProvider.notifier)
                .removeBaseFolder(folder.id),
          ),
        ],
      ),
    );
  }
}

/// Compact inline editor for one base folder's scan depth -- a slimmed-down
/// sibling of [_NumberField] (no label/border) sized to sit in a folder row
/// next to the checkbox and delete button instead of stacked on its own
/// line.
class _DepthField extends StatefulWidget {
  const _DepthField({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_DepthField> createState() => _DepthFieldState();
}

class _DepthFieldState extends State<_DepthField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(
            horizontal: GbmSpacing.space1,
            vertical: 6,
          ),
        ),
        style: const TextStyle(fontSize: GbmTypography.textSm),
        // Only a parseable non-negative value is committed -- a half-typed
        // field must not momentarily send 0 (which would mean "this base
        // folder is itself the only thing scanned") mid-keystroke.
        onSubmitted: (String text) {
          final int? parsed = int.tryParse(text.trim());
          if (parsed != null && parsed >= 0) widget.onChanged(parsed);
        },
      ),
    );
  }
}

class _GitSection extends ConsumerWidget {
  const _GitSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPreferences prefs = ref.watch(appPreferencesProvider);
    final AppPreferencesNotifier notifier = ref.read(
      appPreferencesProvider.notifier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('全域 GITIGNORE'),
        _SettingSwitch(
          title: '使用全域 gitignore 檔案',
          subtitle:
              '會寫入 core.excludesFile，所以命令列也套用同一份規則。關閉這個 '
              '設定只會移除設定值——檔案本身不會被刪除。',
          value: prefs.globalGitignoreEnabled,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(globalGitignoreEnabled: v),
          ),
        ),
        if (prefs.globalGitignoreEnabled) ...<Widget>[
          const SizedBox(height: GbmSpacing.space2),
          _GitignorePathField(
            initialValue: prefs.globalGitignorePath,
            onChanged: (String v) => notifier.update(
              (AppPreferences p) => p.copyWith(
                globalGitignorePath: v,
                globalGitignoreSource: 'manual',
              ),
            ),
          ),
          if (prefs.globalGitignoreSource == 'imported') ...<Widget>[
            const SizedBox(height: GbmSpacing.space1),
            Text(
              '從 .gitconfig 匯入',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontStyle: FontStyle.italic,
                color: context.gbmColors.textTertiary,
              ),
            ),
          ],
        ],
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('COMMIT 訊息'),
        _SettingSwitch(
          title: 'cherry-pick 時加上「(cherry picked from commit …)」',
          subtitle: '會附加在原始 commit 內文的最後一行。',
          value: prefs.cherryPickAddsSourceLine,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(cherryPickAddsSourceLine: v),
          ),
        ),
      ],
    );
  }
}

class _GitignorePathField extends StatefulWidget {
  const _GitignorePathField({
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_GitignorePathField> createState() => _GitignorePathFieldState();
}

class _GitignorePathFieldState extends State<_GitignorePathField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      style: const TextStyle(fontFamily: GbmTypography.fontMono),
      decoration: const InputDecoration(
        labelText: '全域 gitignore 檔案路徑',
        hintText: '~/.config/git/ignore',
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final GbmThemeVariant variant = ref.watch(themeVariantProvider);
    final AppPreferences prefs = ref.watch(appPreferencesProvider);
    final AppPreferencesNotifier notifier = ref.read(
      appPreferencesProvider.notifier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('主題'),
        Row(
          children: <Widget>[
            const ThemeSwitcherButtons(),
            const SizedBox(width: GbmSpacing.space3),
            Text(
              // 三個主題名稱維持英文 -- 跟 theme_switcher_buttons.dart 的
              // tooltip 是同一組字面值，那個檔案不在 G1 的 30 個對話框範圍
              // 內，只翻這裡會讓同一個名稱一半中文一半英文。
              switch (variant) {
                GbmThemeVariant.darkTechnical => 'Dark technical',
                GbmThemeVariant.lightIde => 'Light IDE',
                GbmThemeVariant.neutralProfessional => 'Neutral professional',
              },
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: GbmSpacing.space2),
        Text(
          '三個主題都定義了完整的 token 集合，所以切換主題不會讓某個面板停留 '
          '在不同主題的樣式上。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textTertiary,
            height: GbmTypography.leadingNormal,
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('程式碼'),
        _SettingSwitch(
          title: '長行自動換行',
          subtitle:
              '套用在所有檔案內容畫面：diff、blame、patch 和衝突解決視窗。'
              '預設關閉——關閉時長行會出現水平捲軸，行號欄會固定在左邊，不會 '
              '跟著程式碼一起捲動。',
          value: prefs.softWrapEnabled,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(softWrapEnabled: v),
          ),
        ),
      ],
    );
  }
}

class _ShortcutsSection extends StatelessWidget {
  const _ShortcutsSection();

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final Map<GbmActionId, GbmKeyboardShortcut> shortcuts = gbmActionShortcuts(
      isMacOS,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('KEYBOARD SHORTCUTS'),
        // Walks gbmMenus rather than the shortcut map directly, so the rows
        // appear grouped in menu order (the order the user learned them in)
        // instead of enum-declaration order.
        for (final GbmMenuModel menu in gbmMenus) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(
              top: GbmSpacing.space2,
              bottom: GbmSpacing.space1,
            ),
            child: Text(
              menu.title,
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontWeight: GbmTypography.weightSemibold,
                color: colors.textTertiary,
              ),
            ),
          ),
          for (final GbmMenuItemModel item in menu.items)
            if (shortcuts[item.id] case final GbmKeyboardShortcut shortcut)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: GbmTypography.textSm,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      shortcut.displayLabel,
                      style: TextStyle(
                        fontFamily: GbmTypography.fontMono,
                        fontSize: GbmTypography.textXs,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}

class _AdvancedSection extends ConsumerWidget {
  const _AdvancedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPreferences prefs = ref.watch(appPreferencesProvider);
    final AppPreferencesNotifier notifier = ref.read(
      appPreferencesProvider.notifier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('確認'),
        _SettingSwitch(
          title: 'force-push 前先確認',
          subtitle: '執行前顯示這次 push 會覆蓋掉多少筆 remote commit。',
          value: prefs.confirmForcePush,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(confirmForcePush: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('記錄'),
        _NumberField(
          label: '記憶體中保留',
          suffix: '筆',
          value: prefs.logMemoryLimit,
          onChanged: (int v) => notifier.update(
            (AppPreferences p) => p.copyWith(logMemoryLimit: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        _NumberField(
          label: '記錄檔保留',
          suffix: '天',
          value: prefs.logRetentionDays,
          onChanged: (int v) => notifier.update(
            (AppPreferences p) => p.copyWith(logRetentionDays: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        Text(
          '密碼、內嵌在 remote URL 裡的 token，以及檔案內容，都不會寫進記錄。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: context.gbmColors.textTertiary,
            height: GbmTypography.leadingNormal,
          ),
        ),
      ],
    );
  }
}
