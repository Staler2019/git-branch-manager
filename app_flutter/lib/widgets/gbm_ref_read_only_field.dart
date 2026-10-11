import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';
import 'gbm_dialog_field_kinds.dart';
import 'gbm_ref_picker.dart';
import 'lucide_icon.dart';

/// A ref a dialog already knows, drawn as DLGS's `ro` field: the label above,
/// the name in mono (`mono: true` on Merge's 來源分支/合入 and Rebase's
/// 重新安置/基於), and the same kind icon [GbmRefPicker]'s rows use, so a
/// locked field reads as the row it replaced
/// (docs/claude-design-demo/merge-rebase-dialogs-spec.html).
///
/// Built on [GbmDialogReadOnlyField], so it inherits that field's no-border
/// sunken box -- ruling ⑤ keeps the shipped look over DLGS's 1px border.
class GbmRefReadOnlyField extends StatelessWidget {
  const GbmRefReadOnlyField({
    super.key,
    required this.label,
    required this.name,
    required this.kind,
  });

  final String label;

  /// What is shown: a branch name, or an already-abbreviated commit.
  final String name;
  final GbmRefKind kind;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmDialogReadOnlyField(
      label: label,
      child: Row(
        children: <Widget>[
          LucideIcon(kind.iconName, size: 12, color: colors.textTertiary),
          const SizedBox(width: GbmSpacing.space2),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: GbmTypography.fontMono),
            ),
          ),
        ],
      ),
    );
  }
}
