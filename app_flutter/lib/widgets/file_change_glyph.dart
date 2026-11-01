import 'package:flutter/widgets.dart';

import '../data/models/working_copy_status.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';
import 'lucide_icon.dart';

/// The status mark drawn in front of a file row's name: a plus for a new file,
/// a minus for a deleted one, an arrow for a rename, and an empty box of the
/// same size for every other kind, so every file name starts at one indent.
///
/// 使用者裁定：「新增檔案為:+，刪除檔案為：-。其他檔案都是照目前這樣，沒有trailing
/// icon，除非有移動屬性，就需要有move icon」；「+ and - use icon, not font」；
/// 「+ - 移動icon固定占位，file name固定縮排」；移動 icon 選 `arrow-right`，
/// 「b,不換顏色」. Spec: docs/claude-design-demo/rename-diff-display-spec.html.
/// The plus and minus take the colours of the trailing `+N`/`-N` badges
/// ([GbmBadgeKind.added]/[GbmBadgeKind.removed]), so a row cannot draw a new
/// file in one green and its line count in another. Sizes (a 14 icon in a
/// 14-wide box, a [GbmSpacing.space1] gap before the name) and the move
/// arrow's [GbmColors.textSecondary] are the user's rulings on the round's
/// design questions.
class FileChangeGlyph extends StatelessWidget {
  const FileChangeGlyph({
    super.key,
    required this.kind,
    this.untracked = false,
  });

  final FileChangeKind kind;

  /// An untracked entry is new whatever [kind] its worktree side reports.
  final bool untracked;

  static const double _size = 14;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final (String, Color)? glyph = untracked
        ? ('plus', colors.diffAddText)
        : switch (kind) {
            FileChangeKind.added => ('plus', colors.diffAddText),
            FileChangeKind.deleted => ('minus', colors.diffDelText),
            FileChangeKind.renamed => ('arrow-right', colors.textSecondary),
            FileChangeKind.modified ||
            FileChangeKind.copied ||
            FileChangeKind.typeChanged ||
            FileChangeKind.modeChanged => null,
          };
    return Padding(
      padding: const EdgeInsets.only(right: GbmSpacing.space1),
      child: SizedBox.square(
        dimension: _size,
        child: switch (glyph) {
          (final String name, final Color color) => Center(
            child: LucideIcon(name, size: _size, color: color),
          ),
          null => null,
        },
      ),
    );
  }
}
