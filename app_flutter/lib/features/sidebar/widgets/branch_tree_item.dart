import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/ref_chip_colors.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import '../../../widgets/lucide_icon.dart';

class BranchTreeItem extends StatelessWidget {
  const BranchTreeItem({
    super.key,
    required this.ref,
    required this.onCheckout,
    this.selected = false,
    this.onSelectedChanged,
    this.onRename,
    this.onDelete,
    this.onNewBranchFromHere,
    this.onMerge,
    this.conflictActive = false,
  });

  final RefInfo ref;
  final VoidCallback onCheckout;
  final bool selected;
  final bool conflictActive;

  /// Null hides the selection checkbox entirely (HEAD can't be
  /// multi-selected for deletion -- see SidebarPanel's doc comment).
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  /// Right-click-only actions (design's `ctxItemsFor('branch')`) beyond
  /// what the `more_vert` fallback menu already offers -- see this class's
  /// `onSecondaryTapDown` wiring below.
  final VoidCallback? onNewBranchFromHere;
  final VoidCallback? onMerge;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RefChipColors chip = refChipColorsFor(
      colors,
      ref.kind,
      isCurrent: ref.isHead,
    );

    final StringBuffer label = StringBuffer(ref.shortName);
    if (ref.isHead) label.write(', current branch');
    if (ref.isGone) {
      label.write(', upstream gone');
    } else if (ref.hasTrackingInfo && (ref.ahead > 0 || ref.behind > 0)) {
      if (ref.ahead > 0) label.write(', ${ref.ahead} ahead');
      if (ref.behind > 0) label.write(', ${ref.behind} behind');
    }

    final Widget row = Container(
      height: GbmSpacing.rowHeightCompact,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
      decoration: BoxDecoration(
        color: ref.isHead ? colors.surfaceSelected : null,
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          if (onSelectedChanged != null)
            Semantics(
              label: 'Select ${ref.shortName} for bulk delete',
              child: Checkbox(
                value: selected,
                onChanged: (value) => onSelectedChanged!(value ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          LucideIcon(
            'git-branch',
            size: 13,
            color: chip.text == colors.textOnAccent ? colors.accent : chip.text,
          ),
          const SizedBox(width: GbmSpacing.space2),
          Expanded(
            child: Text(
              ref.shortName,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                fontWeight: ref.isHead
                    ? GbmTypography.weightSemibold
                    : GbmTypography.weightRegular,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ref.isGone)
            Text(
              'gone',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.danger,
              ),
            )
          else if (ref.hasTrackingInfo && (ref.ahead > 0 || ref.behind > 0))
            Text(
              '${ref.ahead > 0 ? '↑${ref.ahead}' : ''}${ref.behind > 0 ? ' ↓${ref.behind}' : ''}',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
          if (onRename != null || onDelete != null)
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: 'Branch actions',
                icon: Icon(
                  Icons.more_vert,
                  size: 16,
                  color: colors.textTertiary,
                ),
                iconSize: 16,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: () {
                  final RenderBox renderBox =
                      buttonContext.findRenderObject()! as RenderBox;
                  final Offset globalPos = renderBox.localToGlobal(Offset.zero);
                  showGbmContextMenu(
                    buttonContext,
                    globalPos,
                    _buildMenuItems(),
                  );
                },
              ),
            ),
        ],
      ),
    );

    final Widget maybeTooltip = ref.isGone && ref.upstream.isNotEmpty
        ? Tooltip(message: 'Upstream gone: ${ref.upstream}', child: row)
        : row;

    return Semantics(
      button: !ref.isHead,
      label: label.toString(),
      child: GestureDetector(
        onSecondaryTapDown: (details) => _openContextMenu(context, details),
        child: InkWell(
          onTap: (ref.isHead || conflictActive) ? null : onCheckout,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          child: maybeTooltip,
        ),
      ),
    );
  }

  /// `ctxItemsFor('branch')` from gbm_context_menus.dart's 05-B (Local
  /// branch), scoped to what this app already has a real destination for.
  /// "Rebase current onto here" and "Compare with…" are omitted (no
  /// per-branch entry point exists yet -- a targeted rebase/compare would
  /// need the same UI as its repository-level peer, not yet surfaced),
  /// so they are left off rather than wired to something that silently does
  /// the wrong thing.
  List<GbmMenuItem> _buildMenuItems() {
    return <GbmMenuItem>[
      if (!ref.isHead)
        GbmMenuItem(
          label: 'Checkout ${ref.shortName}',
          icon: Icons.call_split,
          onTap: conflictActive ? null : onCheckout,
        ),
      if (onNewBranchFromHere != null)
        GbmMenuItem(
          label: 'New branch from here',
          icon: Icons.add,
          onTap: onNewBranchFromHere!,
        ),
      if (onRename != null)
        GbmMenuItem(
          label: 'Rename branch',
          icon: Icons.edit_outlined,
          onTap: onRename!,
        ),
      if (onMerge != null)
        GbmMenuItem(
          label: 'Merge into current branch',
          icon: Icons.call_merge,
          onTap: onMerge!,
        ),
      GbmMenuItem(
        label: 'Copy branch name',
        icon: Icons.copy,
        onTap: () => Clipboard.setData(ClipboardData(text: ref.shortName)),
      ),
      if (onDelete != null) ...<GbmMenuItem>[
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Delete branch',
          icon: Icons.delete_outline,
          danger: true,
          onTap: onDelete!,
        ),
      ],
    ];
  }

  void _openContextMenu(BuildContext context, TapDownDetails details) {
    showGbmContextMenu(context, details.globalPosition, _buildMenuItems());
  }
}
