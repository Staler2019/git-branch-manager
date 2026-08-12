import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/repo_state.dart' as model;
import '../../../theme/gbm_theme.dart';
import '../../../theme/theme_mode_provider.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_icon_button.dart';
import '../../../widgets/lucide_icon.dart';

class TopBar extends ConsumerWidget {
  const TopBar({
    super.key,
    required this.repoName,
    required this.repoState,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onBack,
  });

  final String repoName;
  final model.RepoState? repoState;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final GbmThemeVariant activeVariant = ref.watch(themeVariantProvider);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: 'Repositories',
          ),
          Text(
            repoName,
            style: TextStyle(
              fontSize: GbmTypography.textMd,
              fontWeight: GbmTypography.weightSemibold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: GbmSpacing.space3),
          if (repoState != null)
            Text(
              repoState!.describe,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          const Spacer(),
          if (isRefreshing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(
            label: 'Refresh',
            icon: LucideIcon(
              'refresh-cw',
              size: 14,
              color: colors.textSecondary,
            ),
            onPressed: isRefreshing ? null : onRefresh,
          ),
          const SizedBox(width: GbmSpacing.space2),
          Container(
            width: 1,
            height: 20,
            color: colors.borderSubtle,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          for (final _ThemeSwatch swatch in _themeSwatches)
            GbmIconButton(
              icon: Icon(swatch.icon, size: 16),
              tooltip: swatch.label,
              active: activeVariant == swatch.variant,
              onPressed: () => ref
                  .read(themeVariantProvider.notifier)
                  .setVariant(swatch.variant),
            ),
        ],
      ),
    );
  }
}

class _ThemeSwatch {
  const _ThemeSwatch(this.variant, this.label, this.icon);
  final GbmThemeVariant variant;
  final String label;
  final IconData icon;
}

/// The design doc's three top-bar theme swatches, in the same order as
/// [GbmThemeVariant]'s declaration.
const List<_ThemeSwatch> _themeSwatches = <_ThemeSwatch>[
  _ThemeSwatch(
    GbmThemeVariant.darkTechnical,
    'Dark technical',
    Icons.dark_mode_outlined,
  ),
  _ThemeSwatch(
    GbmThemeVariant.lightIde,
    'Light IDE',
    Icons.light_mode_outlined,
  ),
  _ThemeSwatch(
    GbmThemeVariant.neutralProfessional,
    'Neutral professional',
    Icons.contrast,
  ),
];
