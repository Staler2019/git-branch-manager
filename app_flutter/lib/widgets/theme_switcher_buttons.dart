import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_mode_provider.dart';
import '../theme/tokens.dart';
import 'gbm_icon_button.dart';

/// The design doc's three theme swatches (`.gbm-iconbtn` row), shared by
/// every surface that needs a theme-switching entry point -- currently
/// [TopBar] (workspace) and [RepoListScreen] (the app's actual initial
/// screen, which previously had no way to reach `neutralProfessional` at
/// all once the old [ThemeMode]-based `_ThemeMenu` was removed there).
class ThemeSwitcherButtons extends ConsumerWidget {
  const ThemeSwitcherButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmThemeVariant activeVariant = ref.watch(themeVariantProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
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
    );
  }
}

class _ThemeSwatch {
  const _ThemeSwatch(this.variant, this.label, this.icon);
  final GbmThemeVariant variant;
  final String label;
  final IconData icon;
}

/// In the same order as [GbmThemeVariant]'s declaration.
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
