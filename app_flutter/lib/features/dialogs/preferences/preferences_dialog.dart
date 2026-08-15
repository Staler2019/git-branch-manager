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
import '../../../theme/gbm_theme.dart';
import '../../../theme/theme_mode_provider.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/theme_switcher_buttons.dart';

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
        const _SectionHeading('AUTOMATIC FETCH'),
        _SettingSwitch(
          title: 'Fetch the open repository in the background',
          subtitle:
              'Only the repository currently open. A plain fetch — the '
              'working tree is never touched. The timer resets when you '
              'switch repository.',
          value: prefs.autoFetchEnabled,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(autoFetchEnabled: v),
          ),
        ),
        if (prefs.autoFetchEnabled) ...<Widget>[
          const SizedBox(height: GbmSpacing.space2),
          _NumberField(
            label: 'Fetch every',
            suffix: 'minutes',
            value: prefs.autoFetchMinutes,
            onChanged: (int v) => notifier.update(
              (AppPreferences p) => p.copyWith(autoFetchMinutes: v),
            ),
          ),
          _SettingSwitch(
            title: 'Prune while fetching',
            subtitle:
                'Also drop remote-tracking refs whose branch is gone on the '
                'remote.',
            value: prefs.autoFetchPrune,
            onChanged: (bool v) => notifier.update(
              (AppPreferences p) => p.copyWith(autoFetchPrune: v),
            ),
          ),
        ],
        const SizedBox(height: GbmSpacing.space2),
        Text(
          'Background fetches never open a dialog when they fail — the result '
          'shows up in ahead/behind counts, the gone markers, and the log.',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: context.gbmColors.textTertiary,
            height: GbmTypography.leadingNormal,
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('OPENING REPOSITORIES'),
        _SettingSwitch(
          title: 'Remember repositories opened manually',
          subtitle:
              'Repositories opened with Open repository… are kept in their own '
              'list, separate from the scanned base folders — so a one-off '
              'project does not require changing your scan settings.',
          value: prefs.recordManualOpens,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(recordManualOpens: v),
          ),
        ),
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
      (int acc, BaseFolderRecord f) =>
          f.lastScanMs > acc ? f.lastScanMs : acc,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('BASE FOLDERS'),
        if (discovery.baseFolders.isEmpty)
          Text(
            'No base folders yet. Add one from the repository list screen.',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textTertiary,
            ),
          )
        else
          for (final BaseFolderRecord folder in discovery.baseFolders)
            _BaseFolderRow(folder: folder),
        const SizedBox(height: GbmSpacing.space2),
        Text(
          '${discovery.repos.length} repositories across $enabledFolders '
          'enabled folder(s)'
          '${slowestScanMs > 0 ? ' · slowest scan ${slowestScanMs}ms' : ''}.',
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
        const _SectionHeading('AUTOMATIC SCAN'),
        _SettingSwitch(
          title: 'Rescan base folders in the background',
          subtitle:
              'A low-priority job — it only ever appears folded into the '
              'status bar task count. When off, scanning happens only on '
              'Rescan now.',
          value: prefs.autoScanEnabled,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(autoScanEnabled: v),
          ),
        ),
        if (prefs.autoScanEnabled) ...<Widget>[
          const SizedBox(height: GbmSpacing.space2),
          _NumberField(
            label: 'Rescan every',
            suffix: 'minutes',
            value: prefs.autoScanMinutes,
            onChanged: (int v) => notifier.update(
              (AppPreferences p) => p.copyWith(autoScanMinutes: v),
            ),
          ),
        ],
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('MANUALLY OPENED'),
        Text(
          recents.isEmpty
              ? 'Nothing recorded yet.'
              : '${recents.length} recorded · most recent: '
                    '${recents.first.workDir}',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: GbmSpacing.space1),
        Text(
          'Clearing this list only forgets the entries — nothing on disk is '
          'deleted.',
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

class _BaseFolderRow extends ConsumerWidget {
  const _BaseFolderRow({required this.folder});

  final BaseFolderRecord folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: GbmSpacing.space1),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: folder.enabled,
            visualDensity: VisualDensity.compact,
            onChanged: (bool? value) => ref
                .read(discoveryProvider.notifier)
                .setBaseFolderEnabled(folder.id, value ?? true),
          ),
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
                  'depth ${folder.maxDepth} · ${folder.lastScanDirs} '
                  'director(ies) scanned',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: colors.danger),
            tooltip: 'Remove',
            onPressed: () =>
                ref.read(discoveryProvider.notifier).removeBaseFolder(folder.id),
          ),
        ],
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
        const _SectionHeading('GLOBAL GITIGNORE'),
        _SettingSwitch(
          title: 'Use a global gitignore file',
          subtitle:
              'Writes core.excludesFile, so the same rules apply on the '
              'command line. Turning this off removes the setting — the file '
              'itself is left in place.',
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
              (AppPreferences p) => p.copyWith(globalGitignorePath: v),
            ),
          ),
        ],
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('COMMIT MESSAGES'),
        _SettingSwitch(
          title: 'Add "(cherry picked from commit …)" when cherry-picking',
          subtitle:
              'Appended as a trailing line to the original commit body.',
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
        labelText: 'Path to the global gitignore file',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading('THEME'),
        Row(
          children: <Widget>[
            const ThemeSwitcherButtons(),
            const SizedBox(width: GbmSpacing.space3),
            Text(
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
          'All three themes define the full token set, so switching never '
          'leaves a panel styled by a different theme.',
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
        const _SectionHeading('CONFIRMATIONS'),
        _SettingSwitch(
          title: 'Confirm before force-pushing',
          subtitle:
              'Shows how many remote commits would be overwritten before the '
              'push runs.',
          value: prefs.confirmForcePush,
          onChanged: (bool v) => notifier.update(
            (AppPreferences p) => p.copyWith(confirmForcePush: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space4),
        const _SectionHeading('LOG'),
        _NumberField(
          label: 'Keep in memory',
          suffix: 'entries',
          value: prefs.logMemoryLimit,
          onChanged: (int v) =>
              notifier.update((AppPreferences p) => p.copyWith(logMemoryLimit: v)),
        ),
        const SizedBox(height: GbmSpacing.space2),
        _NumberField(
          label: 'Keep log files for',
          suffix: 'days',
          value: prefs.logRetentionDays,
          onChanged: (int v) => notifier.update(
            (AppPreferences p) => p.copyWith(logRetentionDays: v),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        Text(
          'Credentials, tokens embedded in remote URLs, and file contents are '
          'never written to the log.',
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
