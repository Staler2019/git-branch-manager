import 'package:flutter/material.dart';

import '../../../data/models/repo_state.dart' as model;
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/lucide_icon.dart';

class TopBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(color: colors.surfacePanel, border: Border(bottom: BorderSide(color: colors.borderSubtle))),
      child: Row(
        children: <Widget>[
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back, size: 18), tooltip: 'Repositories'),
          Text(repoName, style: TextStyle(fontSize: GbmTypography.textMd, fontWeight: GbmTypography.weightSemibold, color: colors.textPrimary)),
          const SizedBox(width: GbmSpacing.space3),
          if (repoState != null)
            Text(repoState!.describe, style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
          const Spacer(),
          if (isRefreshing) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(
            label: 'Refresh',
            icon: LucideIcon('refresh-cw', size: 14, color: colors.textSecondary),
            onPressed: isRefreshing ? null : onRefresh,
          ),
        ],
      ),
    );
  }
}
