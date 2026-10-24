import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../actions/gbm_menu_model.dart';
import '../../../actions/gbm_shortcuts.dart';
import '../../../data/models/base_folder_record.dart';
import '../../../data/models/external_app_entry.dart';
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
import '../../../widgets/gbm_input_decoration.dart';
import '../../../widgets/lucide_icon.dart';
import '../../../widgets/gbm_kbd_chip.dart';
import '../../../widgets/theme_switcher_buttons.dart';
import '../../update/auto_update_check.dart';
import 'preferences_section.dart';

export 'preferences_section.dart';

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
  const PreferencesDialogContent({
    super.key,
    this.initialSection = PreferencesSection.general,
    this.originWorkDir,
  });

  /// The repository window it was opened over, passed on to Update (see
  /// [AboutDialogContent.originWorkDir]).
  final String? originWorkDir;

  /// Where the dialog opens. `Edit apps…` in the worktree panel's ▾ list
  /// passes [PreferencesSection.externalApps] (ruling D5) through
  /// [RoutePaths.preferencesDialogPath]; every other entry point opens on
  /// General, as it always has.
  final PreferencesSection initialSection;

  @override
  ConsumerState<PreferencesDialogContent> createState() =>
      _PreferencesDialogContentState();
}

class _PreferencesDialogContentState
    extends ConsumerState<PreferencesDialogContent> {
  late PreferencesSection _section = widget.initialSection;

  // Section names stay English -- `PREFNAV`'s own six names are these exact
  // English words (G1i; spec-auditor confirmed the app already matches).
  static String label(PreferencesSection section) => switch (section) {
    PreferencesSection.general => 'General',
    PreferencesSection.repositorySources => 'Repository sources',
    PreferencesSection.git => 'Git',
    PreferencesSection.appearance => 'Appearance',
    PreferencesSection.externalApps => 'External apps',
    PreferencesSection.shortcuts => 'Shortcuts',
    PreferencesSection.advanced => 'Advanced',
    PreferencesSection.developer => 'Developer',
  };

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return GbmDialogShell(
      title: 'Preferences',
      actionId: GbmActionId.filePreferences,
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
                    PreferencesSection.general => _GeneralSection(
                      originWorkDir: widget.originWorkDir,
                    ),
                    PreferencesSection.repositorySources =>
                      const _RepositorySourcesSection(),
                    PreferencesSection.git => const _GitSection(),
                    PreferencesSection.appearance => const _AppearanceSection(),
                    PreferencesSection.externalApps =>
                      const _ExternalAppsSection(),
                    PreferencesSection.shortcuts => const _ShortcutsSection(),
                    PreferencesSection.advanced => const _AdvancedSection(),
                    PreferencesSection.developer => const _DeveloperSection(),
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
    // `.gbm-row:hover` in the mockup's nav. The selected fill sits on the
    // child Container, above the ink, so a selected entry keeps it on hover
    // as `.gbm-row.selected` does.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.surfaceHover,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
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
    final GbmColors colors = context.gbmColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space1),
        SizedBox(
          width: 200,
          height: GbmSpacing.inputHeight,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: gbmInputDecoration(
              colors: colors,
              suffixText: widget.suffix.isEmpty ? null : widget.suffix,
            ),
            // Only a parseable positive value is committed -- a half-typed
            // field must not momentarily persist 0 and change behaviour
            // mid-keystroke.
            onChanged: (String text) {
              final int? parsed = int.tryParse(text.trim());
              if (parsed != null && parsed > 0) widget.onChanged(parsed);
            },
          ),
        ),
      ],
    );
  }
}

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection({this.originWorkDir});

  /// Passed on to Update; see [PreferencesDialogContent.originWorkDir].
  final String? originWorkDir;

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
        // Read by AutoFetchHost (`features/workspace/widgets/`). Spec P11
        // item 9 for what it does, plus three user rulings the spec does not
        // carry: 「Fetch on open 跟開關綁定」, 「開 dialog 時都不能做背景
        // fetch」 and 「Auth/HostKey 失敗 → 暫停自動 fetch，直到手動 fetch 成
        // 功；status bar + log 說明」. The failure wording is ERRCASES' row
        // 「自動 fetch 失敗、網路不通 → Status bar + log … 下次排程自動重試」.
        _SettingSwitch(
          title: '在背景 fetch 目前開啟的 repository',
          subtitle: '開啟 repository 時與每隔設定的分鐘數各 fetch 一次，不會更動 working tree。',
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
          '失敗時不彈窗；認證失敗會暫停，直到手動 Fetch 成功。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: context.gbmColors.textTertiary,
            height: GbmTypography.leadingNormal,
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
          subtitle: '啟動時檢查有沒有新版本，一天最多一次。',
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
              onPressed: () => context.pushReplacement(
                RoutePaths.updateDialogPath(originWorkDir: originWorkDir),
              ),
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
                  '啟動檢查會跳過 ${prefs.skippedVersion} 版。',
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
              child: SizedBox(
                height: GbmSpacing.inputHeight,
                child: TextField(
                  controller: _pathController,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  decoration: gbmInputDecoration(
                    colors: colors,
                    hintText: '要掃描的資料夾，例如 /home/you/code',
                  ),
                  onSubmitted: (_) => _addAndScan(),
                ),
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
          '清空清單不會刪除磁碟上的 repository。',
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
        const _SectionHeading('COMMIT 訊息'),
        _SettingSwitch(
          title: '（預設）cherry-pick 時加上「(cherry picked from commit …)」',
          subtitle: '會附加在原始 commit 內文的最後一行。',
          value: prefs.cherryPickAddsSourceLine,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(cherryPickAddsSourceLine: v),
          ),
        ),
        _SettingSwitch(
          title: '（預設）merge／squash 時用 git 準備好的訊息覆蓋 commit 框',
          subtitle: '關閉時，只有 commit 框是空的才會帶入。',
          value: prefs.overwriteWithPreparedMessage,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(overwriteWithPreparedMessage: v),
          ),
        ),
      ],
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
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('程式碼'),
        _SettingSwitch(
          title: '長行自動換行',
          subtitle: '套用在 diff、blame、patch 和衝突解決畫面。',
          value: prefs.softWrapEnabled,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(softWrapEnabled: v),
          ),
        ),
      ],
    );
  }
}

/// External apps -- the worktree panel's ▾ list (open-with-apps-spec.html,
/// screen 2). Every change is written at once, as the rest of this dialog
/// is; only [ExternalAppEntry]'s factory decides what may be written. An
/// edit it rejects -- an emptied field included -- is not written: the row
/// keeps the stored value and says why, the way [_NumberField] never
/// persists a half-typed number.
class _ExternalAppsSection extends ConsumerStatefulWidget {
  const _ExternalAppsSection();

  @override
  ConsumerState<_ExternalAppsSection> createState() =>
      _ExternalAppsSectionState();
}

class _ExternalAppsSectionState extends ConsumerState<_ExternalAppsSection> {
  final TextEditingController _newLabel = TextEditingController();
  final TextEditingController _newCommand = TextEditingController();
  String? _addRejection;

  @override
  void dispose() {
    _newLabel.dispose();
    _newCommand.dispose();
    super.dispose();
  }

  void _store(List<ExternalAppEntry> apps) => ref
      .read(appPreferencesProvider.notifier)
      .update((AppPreferences p) => p.copyWith(externalApps: apps));

  void _move(List<ExternalAppEntry> apps, int from, int to) {
    final List<ExternalAppEntry> next = List<ExternalAppEntry>.of(apps);
    next.insert(to, next.removeAt(from));
    _store(next);
  }

  void _add(List<ExternalAppEntry> apps) {
    switch (ExternalAppEntry.create(
      label: _newLabel.text,
      command: _newCommand.text,
      newId: () => 'app-${DateTime.now().microsecondsSinceEpoch}',
    )) {
      case ExternalAppEntryAccepted(:final ExternalAppEntry entry):
        _store(<ExternalAppEntry>[...apps, entry]);
        _newLabel.clear();
        _newCommand.clear();
        setState(() => _addRejection = null);
      case ExternalAppEntryRejected(:final String reason):
        setState(() => _addRejection = reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<ExternalAppEntry> apps = ref
        .watch(appPreferencesProvider)
        .externalApps;
    final bool canAdd =
        _newLabel.text.trim().isNotEmpty && _newCommand.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('開啟方式'),
        for (final (int i, ExternalAppEntry app) in apps.indexed)
          _ExternalAppRow(
            key: ValueKey<String>('external-app-row-${app.id}'),
            app: app,
            onChanged: (ExternalAppEntry edited) => _store(<ExternalAppEntry>[
              for (final ExternalAppEntry a in apps)
                a.id == edited.id ? edited : a,
            ]),
            onUp: i == 0 ? null : () => _move(apps, i, i - 1),
            onDown: i == apps.length - 1 ? null : () => _move(apps, i, i + 1),
            onRemove: () => _store(<ExternalAppEntry>[
              for (final ExternalAppEntry a in apps)
                if (a.id != app.id) a,
            ]),
          ),
        const SizedBox(height: GbmSpacing.space2),
        Row(
          children: <Widget>[
            SizedBox(
              width: 140,
              height: GbmSpacing.inputHeight,
              child: TextField(
                key: const ValueKey<String>('external-app-new-label'),
                controller: _newLabel,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
                decoration: gbmInputDecoration(colors: colors, hintText: '名稱'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: GbmSpacing.space2),
            Expanded(
              child: SizedBox(
                height: GbmSpacing.inputHeight,
                child: TextField(
                  key: const ValueKey<String>('external-app-new-command'),
                  controller: _newCommand,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    fontFamily: GbmTypography.fontMono,
                    color: colors.textPrimary,
                  ),
                  decoration: gbmInputDecoration(
                    colors: colors,
                    hintText: '指令，例如 code .',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => canAdd ? _add(apps) : null,
                ),
              ),
            ),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(
              label: 'Add',
              kind: GbmButtonKind.primary,
              onPressed: canAdd ? () => _add(apps) : null,
            ),
          ],
        ),
        gbmFieldError(colors: colors, error: _addRejection),
        const SizedBox(height: GbmSpacing.space2),
        Text(
          '在 worktree 資料夾裡執行（macOS／Linux 用 login shell，Windows 用 cmd）；{path} 會換成 worktree 的完整路徑（Windows 換成 .）。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textTertiary,
            height: GbmTypography.leadingNormal,
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        Text(
          '名稱或指令清空時不會存檔，會保留原本的值。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textTertiary,
            height: GbmTypography.leadingNormal,
          ),
        ),
      ],
    );
  }
}

/// One stored entry: name and command fields, reorder, remove, and the
/// reject hint under it while the fields hold something the factory
/// refused.
class _ExternalAppRow extends StatefulWidget {
  const _ExternalAppRow({
    super.key,
    required this.app,
    required this.onChanged,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final ExternalAppEntry app;
  final ValueChanged<ExternalAppEntry> onChanged;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRemove;

  @override
  State<_ExternalAppRow> createState() => _ExternalAppRowState();
}

class _ExternalAppRowState extends State<_ExternalAppRow> {
  late final TextEditingController _label = TextEditingController(
    text: widget.app.label,
  );
  late final TextEditingController _command = TextEditingController(
    text: widget.app.command,
  );
  String? _rejection;

  @override
  void dispose() {
    _label.dispose();
    _command.dispose();
    super.dispose();
  }

  void _edit() {
    switch (widget.app.edit(label: _label.text, command: _command.text)) {
      case ExternalAppEntryAccepted(:final ExternalAppEntry entry):
        setState(() => _rejection = null);
        widget.onChanged(entry);
      case ExternalAppEntryRejected(:final String reason):
        setState(() => _rejection = reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String id = widget.app.id;
    final bool bad = _rejection != null;
    Widget move(String key, String icon, String tip, VoidCallback? onTap) =>
        IconButton(
          key: ValueKey<String>('external-app-$key-$id'),
          icon: LucideIcon(
            icon,
            size: 16,
            color: onTap == null
                ? colors.textTertiary.withValues(alpha: 0.45)
                : colors.textTertiary,
          ),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: GbmSpacing.space1),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 140,
                height: GbmSpacing.inputHeight,
                child: TextField(
                  key: ValueKey<String>('external-app-label-$id'),
                  controller: _label,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  decoration: gbmInputDecoration(colors: colors),
                  onChanged: (_) => _edit(),
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              Expanded(
                child: SizedBox(
                  height: GbmSpacing.inputHeight,
                  child: TextField(
                    key: ValueKey<String>('external-app-command-$id'),
                    controller: _command,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      fontFamily: GbmTypography.fontMono,
                      color: colors.textPrimary,
                    ),
                    decoration: gbmInputDecoration(
                      colors: colors,
                      hasError: bad,
                    ),
                    onChanged: (_) => _edit(),
                  ),
                ),
              ),
              move('up', 'arrow-up', '上移', widget.onUp),
              move('down', 'arrow-down', '下移', widget.onDown),
              IconButton(
                key: ValueKey<String>('external-app-remove-$id'),
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: colors.danger,
                ),
                tooltip: '移除',
                onPressed: widget.onRemove,
              ),
            ],
          ),
        ),
        if (_rejection case final String reason)
          // Under the command field, as the spec's reject hint draws it.
          Padding(
            padding: const EdgeInsets.only(
              left: 140 + GbmSpacing.space2,
              bottom: GbmSpacing.space1,
            ),
            child: gbmFieldError(
              colors: colors,
              error: '$reason，這次修改沒有存檔（仍是 ${widget.app.command}）',
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
                    GbmKbdChip(label: shortcut.displayLabel),
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
          subtitle: '分支和 remote 分岔、要 force-push 時，先顯示會覆蓋多少筆 remote commit；關閉後直接 force-push。',
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
          '密碼、remote URL 裡的 token 與檔案內容不會寫進記錄。',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: context.gbmColors.textTertiary,
            height: GbmTypography.leadingNormal,
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('GIT 指令逾時倍率'),
        _TimeoutMultiplierControl(
          value: prefs.gitTimeoutMultiplier,
          onChanged: (int v) => notifier.update(
            (AppPreferences p) => p.copyWith(gitTimeoutMultiplier: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        Text(
          'Log 常出現 TIMEOUT 時調高，從下一個指令開始生效。',
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

/// 「拖拉四段＋右側自由輸入倍率」 -- design spec
/// `docs/claude-design-demo/slow-machine-timeouts-spec.html`, screen 1. The
/// slider snaps to [_stops]; the field takes any whole multiplier >= 1 (core
/// refuses less), and an off-stop value rests the slider on the nearest
/// lower stop while the field keeps the exact number. No seconds are shown,
/// by ruling: the Log's own limit column is where a deadline is read.
class _TimeoutMultiplierControl extends StatefulWidget {
  const _TimeoutMultiplierControl({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_TimeoutMultiplierControl> createState() =>
      _TimeoutMultiplierControlState();
}

class _TimeoutMultiplierControlState extends State<_TimeoutMultiplierControl> {
  static const List<int> _stops = <int>[1, 2, 4, 8];

  late final TextEditingController _controller = TextEditingController(
    text: widget.value.toString(),
  );

  @override
  void didUpdateWidget(covariant _TimeoutMultiplierControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A slider drag changes the value from outside the field; an edit in the
    // field must not be rewritten under the caret while it is being typed.
    if (widget.value.toString() != _controller.text &&
        int.tryParse(_controller.text.trim()) != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static int _stopIndexFor(int value) {
    int index = 0;
    for (int i = 0; i < _stops.length; i++) {
      if (value >= _stops[i]) index = i;
    }
    return index;
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final int stopIndex = _stopIndexFor(widget.value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: GbmSpacing.inputHeight,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: colors.accent,
                    inactiveTrackColor: colors.borderDefault,
                    thumbColor: colors.accent,
                    activeTickMarkColor: colors.borderStrong,
                    inactiveTickMarkColor: colors.borderStrong,
                    overlayColor: colors.accentSubtle,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    key: const Key('gitTimeoutSlider'),
                    min: 0,
                    max: (_stops.length - 1).toDouble(),
                    divisions: _stops.length - 1,
                    value: stopIndex.toDouble(),
                    onChanged: (double v) {
                      final int next = _stops[v.round()];
                      _controller.text = next.toString();
                      widget.onChanged(next);
                    },
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  for (int i = 0; i < _stops.length; i++)
                    Text(
                      '${_stops[i]}\u00d7',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        fontWeight: i == stopIndex
                            ? GbmTypography.weightSemibold
                            : GbmTypography.weightRegular,
                        color: i == stopIndex
                            ? colors.textPrimary
                            : colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: GbmSpacing.space4),
        SizedBox(
          width: 88,
          height: GbmSpacing.inputHeight,
          child: TextField(
            key: const Key('gitTimeoutField'),
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: gbmInputDecoration(
              colors: colors,
              suffixText: '\u00d7',
            ),
            onChanged: (String text) {
              final int? parsed = int.tryParse(text.trim());
              if (parsed != null && parsed >= 1) widget.onChanged(parsed);
            },
          ),
        ),
      ],
    );
  }
}

/// Not from the spec -- [PreferencesSection.developer]'s own doc comment
/// records why. Every switch here reuses [_SectionHeading]/[_SettingSwitch]
/// verbatim with no new geometry, spacing, or numeric value of any kind --
/// the whole surface is copy text and boolean wiring, so there is nothing
/// here for a spec citation to trace.
class _DeveloperSection extends ConsumerWidget {
  const _DeveloperSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPreferences prefs = ref.watch(appPreferencesProvider);
    final AppPreferencesNotifier notifier = ref.read(
      appPreferencesProvider.notifier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('刷新分層'),
        _SettingSwitch(
          title: '刷新期間保留舊的 diff',
          subtitle: '刷新時，內容沒變的檔案保留已載入的 diff。',
          value: prefs.keepDiffDuringRefresh,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(keepDiffDuringRefresh: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        _SettingSwitch(
          title: '分層刷新',
          subtitle: '切回視窗時先更新目前分支與 working copy，其餘稍後再更新。',
          value: prefs.tieredRefresh,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(tieredRefresh: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        // Headings name the screen area a switch changes -- 「依照畫面範圍去
        // 製作標題，像是狀態列、log之類」 -- not the branch it came from.
        const _SectionHeading('狀態列'),
        _SettingSwitch(
          title: '在狀態列顯示刷新耗時',
          subtitle: '在狀態列顯示切回視窗後 refs／status／diff／bg 各自的毫秒數。',
          value: prefs.showRefreshTimings,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(showRefreshTimings: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('LOG'),
        _SettingSwitch(
          title: '在 Log 顯示每個指令的時限',
          subtitle: 'Log 多一欄，顯示每個指令的時限。',
          value: prefs.showLogTimeouts,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(showLogTimeouts: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        _SettingSwitch(
          title: '在 Log 顯示欄名列',
          subtitle: 'Log 最上面顯示欄名。',
          value: prefs.showLogColumnHeaders,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(showLogColumnHeaders: v),
          ),
        ),
      ],
    );
  }
}
