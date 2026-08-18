import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/ref_chip_colors.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import '../../../widgets/lucide_icon.dart';
import 'tag_menu_items.dart';

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
    this.onPruneRef,
    this.onDeleteOnRemote,
    this.onFetchRef,
    this.onPushTag,
    this.onCompareRef,
    this.onDeleteTag,
    this.conflictActive = false,
  });

  final RefInfo ref;

  /// Checks out [ref]. For a local branch this is a plain checkout, wired
  /// to a single tap; for a remote-only branch ([RefInfo.kind] ==
  /// [RefKind.remoteBranch] -- see `branch_tree_builder.dart`'s
  /// `mergeLocalAndRemoteBranches`) the caller wires it to create-and-check-
  /// out a new local branch instead, and this widget dispatches it on a
  /// double tap, not a single one (Flutter Desktop Spec's BRANCH_STATES:
  /// "點兩下即 checkout 成本機分支").
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

  /// 05-C actions -- see [_buildMenuItems]'s branches on
  /// `ref.kind == RefKind.remoteBranch` and `ref.isGone`. [onPruneRef] is
  /// wired for both a remote-only row and a gone row (pruning the vanished
  /// remote-tracking ref either way); [onDeleteOnRemote] only for a
  /// remote-only row -- a gone row's "Delete on remote…" is permanently
  /// disabled (see [_buildGoneMenuItems]'s doc comment), so there is
  /// nothing for a caller to wire there. [onFetchRef] is the same: wired
  /// only for a remote-only row -- a gone row's own upstream is already
  /// vanished, so "Fetch this branch" is permanently disabled there too.
  final VoidCallback? onPruneRef;
  final VoidCallback? onDeleteOnRemote;
  final VoidCallback? onFetchRef;

  /// 05-D actions -- see [_buildMenuItems]'s branch on
  /// `ref.kind == RefKind.tag`. [onPushTag] is nullable; see
  /// tag_menu_items.dart's `onPush` doc comment for why (no single
  /// unambiguous remote to push to).
  final VoidCallback? onPushTag;
  final VoidCallback? onCompareRef;
  final VoidCallback? onDeleteTag;

  /// Whether [ref] is a "remote-only" leaf -- see
  /// `branch_tree_builder.dart`'s `mergeLocalAndRemoteBranches` doc comment
  /// -- rather than a real local branch.
  bool get _isRemoteOnly => ref.kind == RefKind.remoteBranch;

  bool get _isTag => ref.kind == RefKind.tag;

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
    } else if (_isRemoteOnly) {
      label.write(
        ', remote only, double-click to checkout as new local branch',
      );
    } else if (ref.hasTrackingInfo && (ref.ahead > 0 || ref.behind > 0)) {
      if (ref.ahead > 0) label.write(', ${ref.ahead} ahead');
      if (ref.behind > 0) label.write(', ${ref.behind} behind');
    }

    // BRANCH_STATES table: gone -> cloud-off + warning; remote-only ->
    // cloud + tertiary (dimmed via the Opacity wrap below); everything else
    // keeps the existing git-branch + chip-derived color.
    final String iconName = ref.isGone
        ? 'cloud-off'
        : (_isRemoteOnly ? 'cloud' : 'git-branch');
    final Color iconColor = ref.isGone
        ? colors.warning
        : _isRemoteOnly
        ? colors.textTertiary
        : (chip.text == colors.textOnAccent ? colors.accent : chip.text);

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
          LucideIcon(iconName, size: 13, color: iconColor),
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
          if (onRename != null ||
              onDelete != null ||
              onPruneRef != null ||
              onDeleteOnRemote != null)
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

    // Spec's BRANCH_STATES: remote-only rows render at .62 opacity --
    // "本機還沒有這條分支" (the local machine doesn't have this branch yet).
    final Widget maybeDim = _isRemoteOnly
        ? Opacity(opacity: 0.62, child: maybeTooltip)
        : maybeTooltip;

    return Semantics(
      button: !ref.isHead,
      label: label.toString(),
      child: GestureDetector(
        onSecondaryTapDown: (details) => _openContextMenu(context, details),
        child: InkWell(
          onTap: _isRemoteOnly
              ? null
              : (ref.isHead || conflictActive)
              ? null
              : onCheckout,
          onDoubleTap: _isRemoteOnly && !conflictActive ? onCheckout : null,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          child: maybeDim,
        ),
      ),
    );
  }

  /// 05-C (remote-only branch), scoped to what this app already has a real
  /// destination for. "Fetch this branch" is wired to [onFetchRef] --
  /// `gbm_remote_fetch()` gained an optional per-ref list, so this fetches
  /// just this one ref rather than approximating with a whole-remote fetch.
  List<GbmMenuItem> _buildRemoteOnlyMenuItems() {
    return <GbmMenuItem>[
      GbmMenuItem(
        label: 'Checkout as new local…',
        icon: Icons.call_split,
        onTap: conflictActive ? null : onCheckout,
      ),
      GbmMenuItem(
        label: 'Fetch this branch',
        icon: Icons.cloud_download_outlined,
        enabled: onFetchRef != null,
        onTap: onFetchRef,
      ),
      GbmMenuItem(
        label: 'Copy branch name',
        icon: Icons.copy,
        onTap: () => Clipboard.setData(ClipboardData(text: ref.shortName)),
      ),
      if (onPruneRef != null)
        GbmMenuItem(
          label: 'Prune this ref',
          icon: Icons.cleaning_services_outlined,
          onTap: onPruneRef!,
        ),
      if (onDeleteOnRemote != null) ...<GbmMenuItem>[
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Delete on remote…',
          icon: Icons.delete_outline,
          danger: true,
          onTap: onDeleteOnRemote!,
        ),
      ],
    ];
  }

  /// 05-C, scoped to a "gone" row (a local branch whose upstream vanished).
  /// The design doc's own target note for 05-C is explicit: "gone 的列只留
  /// Prune 與 Copy，其餘停用" (a gone row keeps only Prune and Copy enabled;
  /// the rest disabled). "Checkout as new local…" doesn't apply -- the
  /// branch already exists locally -- and "Delete on remote…" doesn't
  /// either -- the remote copy is already gone, that's what "gone" means.
  /// Both stay visible but permanently disabled (`onTap: null`) rather than
  /// omitted, matching the spec's own wording of "停用" (disabled) over
  /// removal. "Prune this ref" is the row's real remove action -- it clears
  /// the vanished remote-tracking ref itself (`git branch --delete
  /// --remotes`), leaving the local branch untouched, per BRANCH_STATES's
  /// note: "真正移除 remote-tracking ref 要執行 Prune". "Fetch this branch"
  /// gets the same permanent-disabled treatment as "Checkout as new
  /// local…" and "Delete on remote…" -- a gone row's own upstream is what
  /// vanished, so there is nothing left to fetch until a Prune (or a fresh
  /// push) clears or restores it, matching the spec's own "其餘停用".
  List<GbmMenuItem> _buildGoneMenuItems() {
    return <GbmMenuItem>[
      const GbmMenuItem(
        label: 'Checkout as new local…',
        icon: Icons.call_split,
        enabled: false,
        onTap: null,
      ),
      const GbmMenuItem(
        label: 'Fetch this branch',
        icon: Icons.cloud_download_outlined,
        enabled: false,
        onTap: null,
      ),
      GbmMenuItem(
        label: 'Copy branch name',
        icon: Icons.copy,
        onTap: () => Clipboard.setData(ClipboardData(text: ref.shortName)),
      ),
      if (onPruneRef != null)
        GbmMenuItem(
          label: 'Prune this ref',
          icon: Icons.cleaning_services_outlined,
          onTap: onPruneRef!,
        ),
      const GbmMenuItem.separator(),
      const GbmMenuItem(
        label: 'Delete on remote…',
        icon: Icons.delete_outline,
        danger: true,
        enabled: false,
        onTap: null,
      ),
    ];
  }

  /// `ctxItemsFor('branch')` from gbm_context_menus.dart's 05-B (Local
  /// branch), scoped to what this app already has a real destination for.
  /// "Rebase current onto here" and "Compare with…" are omitted (no
  /// per-branch entry point exists yet -- a targeted rebase/compare would
  /// need the same UI as its repository-level peer, not yet surfaced),
  /// so they are left off rather than wired to something that silently does
  /// the wrong thing.
  List<GbmMenuItem> _buildMenuItems() {
    if (_isTag) {
      return tagMenuItems(
        tagName: ref.shortName,
        onCheckoutDetached: conflictActive ? null : onCheckout,
        onPush: onPushTag,
        // Always wired by SidebarPanel for a tag row -- unlike onPushTag,
        // neither has a "sometimes genuinely unavailable" case (see
        // tag_menu_items.dart's doc comment).
        onCompare: onCompareRef!,
        onDelete: onDeleteTag!,
      );
    }
    if (_isRemoteOnly) {
      return _buildRemoteOnlyMenuItems();
    }
    if (ref.isGone) {
      return _buildGoneMenuItems();
    }
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
