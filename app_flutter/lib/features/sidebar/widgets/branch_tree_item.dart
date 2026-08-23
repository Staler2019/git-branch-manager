import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../actions/gbm_selection_gesture.dart';
import '../../../data/models/ref_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/ref_chip_colors.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import '../../../widgets/lucide_icon.dart';
import 'local_branch_menu_items.dart';
import 'tag_menu_items.dart';

class BranchTreeItem extends StatelessWidget {
  const BranchTreeItem({
    super.key,
    required this.ref,
    required this.onCheckout,
    this.selected = false,
    this.onSelectedChanged,
    this.onSelect,
    this.multiSelectMenuBuilder,
    this.multiSelectMenuTitle,
    this.onCollapseSelectionToThis,
    this.onRename,
    this.onDelete,
    this.onNewBranchFromHere,
    this.onMerge,
    this.onPruneRef,
    this.onDeleteOnRemote,
    this.onFetchRef,
    this.onPushTag,
    this.onCompareRef,
    this.onRebaseOntoHere,
    this.onDeleteTag,
    this.conflictActive = false,
    this.isGonePending = false,
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

  /// Whether the upstream this row points at is in
  /// [RepoSessionState.gonePendingRefs] -- `git remote prune --dry-run` says
  /// it no longer exists on the remote, but nothing has been deleted yet.
  ///
  /// Spec page 02 marks such a row in three stages and this widget covers
  /// the first two (半透明 + 刪除線 + cloud-off, and the `gone` badge on a
  /// local branch that tracks it); only an explicit Remote -> Prune remote
  /// branches performs the third. Computed by [SidebarPanel] through
  /// `gone_marking.dart`'s `isEffectivelyGone`, so this widget stays
  /// presentational with no Riverpod dependency -- same shape as
  /// [conflictActive].
  final bool isGonePending;

  /// [RefInfo.isGone] (git already reports `[gone]`, i.e. the ref is
  /// already pruned locally) or [isGonePending] (the dry run says it will
  /// be). Every gone-shaped rendering decision below reads this rather than
  /// `ref.isGone`, so a row stays marked continuously across a real prune as
  /// the truth hands over from one source to the other.
  bool get _gone => ref.isGone || isGonePending;

  /// Null hides the selection checkbox entirely (HEAD can't be
  /// multi-selected for deletion -- see SidebarPanel's doc comment).
  final ValueChanged<bool>? onSelectedChanged;

  /// Reports a modifier-carrying click for spec page 13's multi-select.
  ///
  /// **Only [SelectionGesture.toggle] and [SelectionGesture.range] reach
  /// here.** A plain click on a local branch row stays what it has always
  /// been in this app -- a checkout -- rather than becoming "select only
  /// this". `MULTIKEYS`' 單擊 row is written for lists generally and the
  /// spec says nothing about the branch tree specifically, so changing the
  /// sidebar's primary interaction on that basis would be a guess with a
  /// large blast radius. History's commit list, which had no competing
  /// single-click meaning, follows `MULTIKEYS` exactly.
  final void Function(SelectionGesture gesture)? onSelect;

  /// Spec page 13's right-click rule for a multi-selection: 「右鍵點在**已
  /// 選中**的項目上不改變 selection，選單標題顯示數量；點在**未選中**的項
  /// 目上先改為只選它、再開選單」.
  ///
  /// Both halves live here rather than in the panel because this widget owns
  /// `onSecondaryTapDown`. [multiSelectMenuBuilder] is non-null only when
  /// this row is *inside* a selection of more than one -- then it replaces
  /// the per-row menu wholesale and [multiSelectMenuTitle] becomes the
  /// menu's header. Otherwise [onCollapseSelectionToThis] runs first, so the
  /// per-row menu that follows can never act on a selection the user can no
  /// longer see.
  final List<GbmMenuItem> Function()? multiSelectMenuBuilder;
  final String? multiSelectMenuTitle;
  final VoidCallback? onCollapseSelectionToThis;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  /// Right-click-only actions (design's `ctxItemsFor('branch')`) beyond
  /// what the `more_vert` fallback menu already offers -- see this class's
  /// `onSecondaryTapDown` wiring below.
  final VoidCallback? onNewBranchFromHere;
  final VoidCallback? onMerge;

  /// 05-B's "Rebase current onto here" -- replays the current branch on top
  /// of this one. Opens the shared rebase-onto dialog pre-filled with this
  /// branch (see RoutePaths.rebaseOntoDialogFor's `target`), rather than a
  /// new per-branch dialog.
  final VoidCallback? onRebaseOntoHere;

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

  /// 05-B's and 05-D's "Compare with…" -- opens a Compare tab with this ref
  /// on the left, leaving the right side to the Compare page's own ref
  /// picker. Same mechanism `_compareStash`/`_compareTag` already use; no
  /// per-branch compare dialog is involved.
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
    if (_gone) {
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
    final String iconName = _gone
        ? 'cloud-off'
        : (_isRemoteOnly ? 'cloud' : 'git-branch');
    final Color iconColor = _gone
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
          // 4:1 against the tracking label below. The label used to be a
          // plain non-flex Text: RenderFlex sizes non-flex children first,
          // so "up 1234 down 5678" took whatever it wanted and left the name
          // whatever remained -- which at the sidebar's 180px minimum, with
          // a few levels of folder indent in front, is close to nothing. The
          // name is what the row is for and it has no icon or tooltip
          // standing in for it, so it is the half that keeps the space.
          Expanded(
            flex: 4,
            child: Text(
              ref.shortName,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                fontWeight: ref.isHead
                    ? GbmTypography.weightSemibold
                    : GbmTypography.weightRegular,
                color: colors.textPrimary,
                // Spec page 02 stage 1: 「該列轉半透明、名稱加刪除線」.
                decoration: _gone ? TextDecoration.lineThrough : null,
                decorationColor: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_gone)
            Flexible(
              child: Text(
                'gone',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.danger,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            )
          else if (ref.hasTrackingInfo && (ref.ahead > 0 || ref.behind > 0))
            Flexible(
              child: Text(
                '${ref.ahead > 0 ? '↑${ref.ahead}' : ''}${ref.behind > 0 ? ' ↓${ref.behind}' : ''}',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
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

    final Widget maybeTooltip = _gone && ref.upstream.isNotEmpty
        ? Tooltip(message: 'Upstream gone: ${ref.upstream}', child: row)
        : row;

    // Spec's BRANCH_STATES: remote-only rows render at .62 opacity --
    // "本機還沒有這條分支" (the local machine doesn't have this branch yet).
    // Spec page 02 stage 1 dims a gone row for a different reason ("this no
    // longer exists on the remote"); the strikethrough on the name is what
    // tells the two apart, since a remote-only row can be either.
    final Widget maybeDim = _isRemoteOnly || _gone
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
              : () {
                  final SelectionGesture gesture = currentSelectionGesture();
                  if (gesture != SelectionGesture.single && onSelect != null) {
                    onSelect!(gesture);
                    return;
                  }
                  if (ref.isHead || conflictActive) return;
                  onCheckout();
                },
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

  /// Dispatches to whichever of the four page-05 groups this row is: 05-D
  /// for a tag, 05-C for a remote-only row, 05-C's disabled subset for a
  /// "gone" row, and 05-B for an ordinary local branch (the fall-through,
  /// built by [localBranchMenuItems]).
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
    if (_gone) {
      return _buildGoneMenuItems();
    }
    return localBranchMenuItems(
      branchName: ref.shortName,
      isCurrent: ref.isHead,
      conflictActive: conflictActive,
      onCheckout: onCheckout,
      onNewBranchFromHere: onNewBranchFromHere,
      onRename: onRename,
      onMerge: onMerge,
      onRebaseOntoHere: onRebaseOntoHere,
      onCompare: onCompareRef,
      onDelete: onDelete,
    );
  }

  void _openContextMenu(BuildContext context, TapDownDetails details) {
    final List<GbmMenuItem> Function()? multi = multiSelectMenuBuilder;
    if (multi != null) {
      showGbmContextMenu(
        context,
        details.globalPosition,
        multi(),
        title: multiSelectMenuTitle,
      );
      return;
    }
    onCollapseSelectionToThis?.call();
    showGbmContextMenu(context, details.globalPosition, _buildMenuItems());
  }
}
