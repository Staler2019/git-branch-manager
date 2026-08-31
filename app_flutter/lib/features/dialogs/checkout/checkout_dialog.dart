import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_row.dart';

/// One row in the searchable list: a local branch, a remote branch, or a tag.
class _CheckoutTarget {
  const _CheckoutTarget({
    required this.name,
    required this.group,
    required this.isRemote,
  });

  final String name;
  final String group;

  /// Remote-only branches check out as a new local branch tracking them --
  /// spec context menu 05-C's "Checkout as new local…".
  final bool isRemote;
}

/// Branch → Checkout… (Ctrl/Cmd+Shift+O).
///
/// Spec page 06: "可搜尋的分支 / tag / commit 清單。working tree 有變更時提供
/// stash 後切換的選項" -- the stash-first checkbox is shown only when the
/// working copy is actually dirty, since offering it on a clean tree would
/// be an option that does nothing.
///
/// Note this is the *pre-emptive* offer. A checkout that git refuses anyway
/// still comes back through `checkoutChoices` and the checkout-recovery
/// dialog (see `RepoSessionState.checkoutChoices`); the two are
/// complementary, not duplicates.
///
/// Routed as `/repo/:repoId/dialogs/checkout`.
class CheckoutDialogContent extends ConsumerStatefulWidget {
  const CheckoutDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<CheckoutDialogContent> createState() =>
      _CheckoutDialogContentState();
}

class _CheckoutDialogContentState extends ConsumerState<CheckoutDialogContent> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selected;
  bool _selectedIsRemote = false;
  bool _stashFirst = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Substring, case-insensitive -- the same matching rule spec page 02 item
  /// 14 specifies for the sidebar branch filter, so the two search fields
  /// behave identically.
  bool _matches(String name) =>
      _query.isEmpty || name.toLowerCase().contains(_query.toLowerCase());

  List<_CheckoutTarget> _targets(RepoSessionState session) {
    final String head = session.refs.head.branchName;
    return <_CheckoutTarget>[
      for (final RefInfo b in session.refs.localBranches)
        if (b.shortName != head && _matches(b.shortName))
          _CheckoutTarget(
            name: b.shortName,
            group: 'Local branches',
            isRemote: false,
          ),
      for (final RefInfo b in session.refs.remoteBranches)
        if (_matches(b.shortName))
          _CheckoutTarget(
            name: b.shortName,
            group: 'Remote branches',
            isRemote: true,
          ),
      for (final RefInfo t in session.refs.tags)
        if (_matches(t.shortName))
          _CheckoutTarget(name: t.shortName, group: 'Tags', isRemote: false),
    ];
  }

  void _submit() {
    final String? target = _selected;
    if (target == null) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .checkout(
          target: target,
          stashFirst: _stashFirst,
          // A remote-only branch has no local counterpart to switch to, so
          // check it out as a new local branch of the same short name.
          createBranch: _selectedIsRemote,
          newBranchName: _selectedIsRemote ? _localNameFor(target) : '',
        );
    context.pop();
  }

  /// `origin/feature/x` -> `feature/x`. Only the first path segment (the
  /// remote name) is dropped, so a branch whose own name contains slashes
  /// survives intact.
  static String _localNameFor(String remoteShortName) {
    final int slash = remoteShortName.indexOf('/');
    return slash == -1 ? remoteShortName : remoteShortName.substring(slash + 1);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<_CheckoutTarget> targets = _targets(session);
    final bool isDirty = session.workingCopyStatus.entries.isNotEmpty;

    // Group headers are emitted inline as the list is walked, so an empty
    // group (everything filtered out) leaves no orphaned heading behind --
    // the same "沒有命中的段落整段隱藏，不留空標題" rule as the sidebar filter.
    return GbmDialogShell(
      title: 'Checkout',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Checkout',
          kind: GbmButtonKind.primary,
          onPressed: _selected == null ? null : _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (String value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search branches, tags and commits',
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search, size: 16),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: targets.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: GbmSpacing.space4,
                    ),
                    child: Text(
                      _query.isEmpty
                          ? 'Nothing to check out.'
                          : 'No branch, tag or commit matches "$_query".',
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: targets.length,
                    itemBuilder: (BuildContext context, int index) {
                      final _CheckoutTarget target = targets[index];
                      // Recomputed per build; itemBuilder is not guaranteed
                      // to run in order, so derive the header from the
                      // previous entry rather than from mutable state.
                      final bool isFirstOfGroup =
                          index == 0 ||
                          targets[index - 1].group != target.group;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (isFirstOfGroup)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: GbmSpacing.space2,
                                bottom: GbmSpacing.space1,
                              ),
                              child: Text(
                                target.group.toUpperCase(),
                                style: TextStyle(
                                  fontSize: GbmTypography.textXs,
                                  fontWeight: GbmTypography.weightSemibold,
                                  color: colors.textTertiary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          GbmRow(
                            selected: _selected == target.name,
                            height: GbmSpacing.rowHeightCompact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: GbmSpacing.space2,
                            ),
                            onTap: () => setState(() {
                              _selected = target.name;
                              _selectedIsRemote = target.isRemote;
                            }),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                target.name,
                                style: TextStyle(
                                  fontSize: GbmTypography.textSm,
                                  color: colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (_selectedIsRemote && _selected != null) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            Text(
              'Creates local branch "${_localNameFor(_selected!)}" tracking $_selected.',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ],
          if (isDirty) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            CheckboxListTile(
              value: _stashFirst,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Stash uncommitted changes first',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                '${session.workingCopyStatus.pendingChangeCount} file(s) have uncommitted changes.',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                ),
              ),
              onChanged: (bool? value) =>
                  setState(() => _stashFirst = value ?? false),
            ),
          ],
        ],
      ),
    );
  }
}
