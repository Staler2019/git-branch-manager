import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_ref_picker.dart';

/// Branch → Checkout… (Ctrl/Cmd+Shift+O).
///
/// Spec page 06: "可搜尋的分支 / tag / commit 清單。working tree 有變更時提供
/// stash 後切換的選項" -- the stash-first checkbox is shown only when the
/// working copy is actually dirty, since offering it on a clean tree would
/// be an option that does nothing.
///
/// The list is [GbmRefPicker], shared with New branch and Add worktree. Its
/// **commit** rows are new: this dialog's own list was branches and tags
/// only, so the row's `how` promised a granularity the widget could not
/// reach ([SPEC-how-column-is-a-requirement]).
///
/// Note this is the *pre-emptive* offer. A checkout that git refuses anyway
/// still comes back through `checkoutChoices` and the checkout-recovery
/// dialog (see `RepoSessionState.checkoutChoices`); the two are
/// complementary, not duplicates.
///
/// **[DRIFT-checkout-dialog-mock-delta] is closed as of this dialog.** The
/// mock's 目前 read-only row (`main · 有25 項未提交變更`) and its
/// radio-on/radio pair (帶著變更切過去 / 先 stash，切完不自動還原) are both
/// drawn now, quoted verbatim from `DLGS`'s Checkout entry. The pair still
/// maps onto the one `_stashFirst` bool `checkout(stashFirst:)` already took
/// -- radio-on is `false`, the default -- so no controller change was
/// needed to close this. The mock's `warn` field (「兩邊都改到的檔案會阻止
/// checkout…」) is deliberately left out: the pin never recorded it as part
/// of the gap, and it describes a failure this dialog cannot predict ahead
/// of the attempt -- that is exactly what `checkoutChoices` and the
/// checkout-recovery dialog above already handle once git refuses.
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
  String? _selected;
  bool _selectedIsRemote = false;
  bool _stashFirst = false;

  /// The branch HEAD is on is left out entirely, because checking it out is
  /// a no-op -- the one place this picker's caller differs from New branch's,
  /// which annotates the same row instead.
  List<GbmRefPickerEntry> _entries(RepoSessionState session) {
    final String head = session.refs.head.branchName;
    return <GbmRefPickerEntry>[
      for (final RefInfo b in session.refs.localBranches)
        if (b.shortName != head)
          GbmRefPickerEntry(name: b.shortName, kind: GbmRefKind.localBranch),
      for (final RefInfo b in session.refs.remoteBranches)
        GbmRefPickerEntry(name: b.shortName, kind: GbmRefKind.remoteBranch),
      for (final RefInfo t in session.refs.tags)
        GbmRefPickerEntry(name: t.shortName, kind: GbmRefKind.tag),
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
    final List<GbmRefPickerEntry> entries = _entries(session);
    final bool isDirty = session.workingCopyStatus.entries.isNotEmpty;
    final String head = session.refs.head.branchName;
    final int pendingCount = session.workingCopyStatus.pendingChangeCount;

    return GbmDialogShell(
      title: 'Checkout',
      actionId: GbmActionId.branchCheckout,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Checkout',
          kind: GbmButtonKind.primary,
          onPressed: _selected == null ? null : _submit,
        ),
      ],
      // Scrollable, like New branch's: the 目前 row plus the radio pair can
      // exceed GbmDialogShell's 560px cap on a short window, and every child
      // here is non-flex ([FLU-renderflex-non-flex-first]).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            GbmRefPicker(
              entries: entries,
              selected: _selected,
              autofocus: true,
              allowCommitHash: true,
              hintText: '可搜尋 branch / tag / commit',
              emptyMessage: '沒有可以切換的項目。',
              onSelected: (GbmRefPickerEntry entry) => setState(() {
                _selected = entry.name;
                _selectedIsRemote = entry.kind == GbmRefKind.remoteBranch;
              }),
            ),
            if (_selectedIsRemote && _selected != null) ...<Widget>[
              const SizedBox(height: GbmSpacing.space2),
              Text(
                '建立本地分支「${_localNameFor(_selected!)}」，追蹤 $_selected。',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: GbmSpacing.space2),
            // DLGS's `ro` field, 「目前」/`main · 有25 項未提交變更` -- quoted
            // verbatim including its punctuation (no space after 有).
            Text(
              isDirty ? '目前 $head · 有$pendingCount 項未提交變更' : '目前 $head',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
            if (isDirty) ...<Widget>[
              const SizedBox(height: GbmSpacing.space2),
              RadioGroup<bool>(
                groupValue: _stashFirst,
                onChanged: (bool? value) =>
                    setState(() => _stashFirst = value ?? _stashFirst),
                child: const Column(
                  children: <Widget>[
                    _StashChoiceOption(value: false, label: '帶著變更切過去'),
                    _StashChoiceOption(value: true, label: '先 stash，切完不自動還原'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// DLGS's `radio-on`/`radio` pair for Checkout: both are value-only, with no
/// separate description, so this stays a plain label -- inventing a subtitle
/// sentence here would draw text the mock never asked for.
class _StashChoiceOption extends StatelessWidget {
  const _StashChoiceOption({required this.value, required this.label});

  final bool value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<bool>(
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: TextStyle(
          fontSize: GbmTypography.textSm,
          color: context.gbmColors.textPrimary,
        ),
      ),
    );
  }
}
