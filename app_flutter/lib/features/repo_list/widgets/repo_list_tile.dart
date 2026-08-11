import 'package:flutter/material.dart';

import '../../../data/models/repo_record.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/lucide_icon.dart';

class RepoListTile extends StatelessWidget {
  const RepoListTile({super.key, required this.repo, required this.onTap});

  final RepoRecord repo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      child: Container(
        height: GbmSpacing.rowHeightComfortable,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
        child: Row(
          children: <Widget>[
            LucideIcon(repo.kind == RepoKind.bare ? 'archive' : 'git-fork', size: 15, color: colors.textSecondary),
            const SizedBox(width: GbmSpacing.space2),
            Expanded(
              child: Text(repo.name, style: TextStyle(fontSize: GbmTypography.textBase, color: colors.textPrimary)),
            ),
            Text(
              repo.workDir,
              style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary),
              overflow: TextOverflow.ellipsis,
            ),
            if (repo.isMissing) ...<Widget>[
              const SizedBox(width: GbmSpacing.space2),
              Text('missing', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
