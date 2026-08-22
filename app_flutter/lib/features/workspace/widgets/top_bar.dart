import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/repo_state.dart' as model;
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/lucide_icon.dart';
import '../../../widgets/theme_switcher_buttons.dart';

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
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          // Closes this repository rather than "going back to the list":
          // there is no repository list to go back to any more (switching is
          // the sidebar's popover, see repo_switcher_popover.dart), so this
          // lands on the welcome screen with nothing open.
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: 'Close repository',
          ),
          // The repository name and state label are the only variable-width
          // things in this bar, and both used to be non-flex Texts with no
          // ellipsis. RenderFlex lays non-flex children out first and only
          // then divides what is left, so a long repository name pushed the
          // trailing controls straight off the right edge -- a thrown
          // overflow in debug/test builds, not just a visual clip. Wrapping
          // them in Flexible moves them out of the non-flex pass; the
          // ellipsis is what makes that shrink legible.
          //
          // `Expanded` around the pair replaces the `Spacer` that used to sit
          // after them. A Spacer is itself a flex child, so it would have
          // competed for the same space and capped the name at its own share
          // (a third) even on a wide window where the full name fits. Here
          // the inner Row's default mainAxisSize.max leaves the same blank
          // gap the Spacer produced, without taking a cut.
          Expanded(
            child: Row(
              children: <Widget>[
                // 4:1 -- the state label is a short fixed vocabulary
                // (MERGING, REBASING, ...) and is also shown in the status
                // bar, so it is the half that should yield first. The
                // repository name has no second home in the window.
                Flexible(
                  flex: 4,
                  child: Text(
                    repoName,
                    style: TextStyle(
                      fontSize: GbmTypography.textMd,
                      fontWeight: GbmTypography.weightSemibold,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: GbmSpacing.space3),
                if (repoState != null)
                  Flexible(
                    child: Text(
                      repoState!.describe,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
              ],
            ),
          ),
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
          const ThemeSwitcherButtons(),
        ],
      ),
    );
  }
}
