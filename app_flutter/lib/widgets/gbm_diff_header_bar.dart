import 'package:flutter/widgets.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// The bar above a diff that names the file: History's and the Working
/// Copy's title bars, and the header of every read-only diff pane (Compare,
/// File History, a stash's file). One widget because they are the same
/// furniture doing the same job, and two copies of its style is how they
/// would come to disagree.
///
/// [text] is the caller's -- `DiffFile.headerText` reads `old → new` for a
/// rename. [trailing] is pinned to the right end; the path elides before it
/// is pushed off. Spec: docs/claude-design-demo/rename-diff-display-spec.html,
/// 畫面 2.
class GbmDiffHeaderBar extends StatelessWidget {
  const GbmDiffHeaderBar({
    super.key,
    required this.text,
    this.trailing = const <Widget>[],
  });

  final String text;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfacePanelRaised,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: <Widget>[
          // Expanded, with no Spacer after it: RenderFlex lays the non-flex
          // trailing controls out first, so a long path elides instead of
          // pushing them off the end. The bars this replaced paired a
          // Flexible with a Spacer, two flex-1 children that split the free
          // space between them, so a short path left the controls stranded
          // mid-bar rather than at the right end.
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}
