// The dialogs' copy, held against the spec's per-element language rule.
//
// 使用者裁定：「現在都是中文的，那就改成中文」. The spec does not simply
// "use Chinese" -- counted from `DLGS` in `spec_logic.js`, it splits by
// element: dialog titles are English 26/0 and primary buttons 26/0, while
// field labels run 3/47 Chinese, options 40/81 and hints 0/13. So this file
// asserts *both* directions on every dialog it covers. A test that only
// looked for the Chinese would pass a dialog whose title had been
// translated too, which is the other way to get this wrong.
//
// The wording is transcribed from `DLGS` wherever the spec describes the
// same control, so most of these strings are quotations rather than
// translations. Where it does not -- merge's fast-forward-only radio, which
// is `--ff-only` and not the spec's plain `--ff` -- the copy is composed in
// the same voice and the divergence is recorded at the call site.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/operation_choice.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/dialogs/checkout/checkout_dialog.dart';
import 'package:gbm_flutter/features/dialogs/checkout_recovery/checkout_recovery_dialog.dart';
import 'package:gbm_flutter/features/dialogs/cherry_pick/cherry_pick_dialog.dart';
import 'package:gbm_flutter/features/dialogs/clean_untracked/clean_untracked_dialog.dart';
import 'package:gbm_flutter/features/dialogs/create_tag/create_tag_dialog.dart';
import 'package:gbm_flutter/features/dialogs/credential/credential_dialog.dart';
import 'package:gbm_flutter/features/dialogs/delete_branch/delete_branch_dialog.dart';
import 'package:gbm_flutter/features/dialogs/delete_branch_recovery/delete_branch_recovery_dialog.dart';
import 'package:gbm_flutter/features/dialogs/delete_branches/delete_branches_dialog.dart';
import 'package:gbm_flutter/features/dialogs/delete_remote_branch/delete_remote_branch_dialog.dart';
import 'package:gbm_flutter/features/dialogs/discard_changes/discard_changes_dialog.dart';
import 'package:gbm_flutter/features/dialogs/discard_changes/discard_changes_request.dart';
import 'package:gbm_flutter/features/dialogs/force_push/force_push_dialog.dart';
import 'package:gbm_flutter/features/dialogs/merge/merge_dialog.dart';
import 'package:gbm_flutter/features/dialogs/new_branch/new_branch_dialog.dart';
import 'package:gbm_flutter/features/dialogs/prune_remote_branches/prune_remote_branches_dialog.dart';
import 'package:gbm_flutter/features/dialogs/rebase_onto/rebase_onto_dialog.dart';
import 'package:gbm_flutter/features/dialogs/rename_branch/rename_branch_dialog.dart';
import 'package:gbm_flutter/features/dialogs/repository_settings/repository_settings_dialog.dart';
import 'package:gbm_flutter/features/dialogs/reset_branch/reset_branch_dialog.dart';
import 'package:gbm_flutter/features/dialogs/restore_file/restore_file_dialog.dart';
import 'package:gbm_flutter/features/dialogs/stash_changes/stash_changes_dialog.dart';
import 'package:gbm_flutter/features/dialogs/undo_last/undo_last_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/tmp/repo',
  gitDir: '/tmp/repo/.git',
);

RefInfo _ref(String shortName) => RefInfo(
  fullName: 'refs/heads/$shortName',
  shortName: shortName,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

final RepoSessionState _state = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[_ref('main'), _ref('feature/lane-allocator')],
    refCountGuardTripped: false,
    totalRefCount: 2,
  ),
);

RepoSessionState _stateFor(String branchName) => RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: HeadInfo(
      kind: HeadKind.branch,
      branchName: branchName,
      fullRef: 'refs/heads/$branchName',
      target: 'aaaa',
    ),
    refs: <RefInfo>[_ref(branchName), _ref('feature/lane-allocator')],
    refCountGuardTripped: false,
    totalRefCount: 2,
  ),
);

RefInfo _remoteRef(String shortName) => RefInfo(
  fullName: 'refs/remotes/$shortName',
  shortName: shortName,
  kind: RefKind.remoteBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

WorkingCopyEntry _wcEntry(String path) => WorkingCopyEntry(
  path: path,
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: 0,
  isSubmodule: false,
  isConflicted: false,
);

// Checkout's own list excludes HEAD's branch entirely (checking it out is a
// no-op), so `main` need not appear in `refs` at all -- only `head` has to
// name it.
final RepoSessionState _checkoutStateWithRemote = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[_remoteRef('origin/wip/askpass')],
    refCountGuardTripped: false,
    totalRefCount: 1,
  ),
);

// Rebase onto's warn banner reads whether the *current* branch (main, here)
// has a remote counterpart -- remoteCounterpartOf() matches an unambiguous
// same-named remote ref even with no explicit upstream config, same as
// _deleteBranchStateWithRemote below, but for `origin/main` rather than a
// different branch's counterpart.
final RepoSessionState _rebaseOntoStateWithRemote = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[
      _ref('main'),
      _ref('feature/lane-allocator'),
      _remoteRef('origin/main'),
    ],
    refCountGuardTripped: false,
    totalRefCount: 3,
  ),
);

final RepoSessionState _newBranchStateWithRemote = _state.copyWith(
  remotes: const <RemoteInfo>[
    RemoteInfo(
      name: 'origin',
      fetchUrl: 'https://example.com/origin.git',
      pushUrl: 'https://example.com/origin.git',
    ),
  ],
);

// deleteBranchRemoteTarget() resolves through remoteCounterpartOf(), which
// matches an unambiguous same-named remote ref even with no explicit
// upstream config -- rule 2 of RemoteBranchIndex.counterpartOf's own doc.
// No `upstream` field needed on the local branch for this one.
final RepoSessionState _deleteBranchStateWithRemote = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[
      _ref('main'),
      _ref('wip/askpass'),
      _remoteRef('origin/wip/askpass'),
    ],
    refCountGuardTripped: false,
    totalRefCount: 3,
  ),
);

RefInfo _trackedLocalRef(
  String shortName, {
  required String upstreamShortName,
  required int ahead,
}) => RefInfo(
  fullName: 'refs/heads/$shortName',
  shortName: shortName,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: 'refs/remotes/$upstreamShortName',
  ahead: ahead,
  behind: 0,
  hasTrackingInfo: true,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

// deleteBranchLines() reads RefInfo.upstream directly (not
// remoteCounterpartOf()), so this fixture needs an actual upstream value,
// unlike _deleteBranchStateWithRemote above.
final RepoSessionState _deleteBranchesState = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[
      _ref('main'),
      _ref('untracked/x'),
      _trackedLocalRef(
        'tracked/y',
        upstreamShortName: 'origin/tracked/y',
        ahead: 2,
      ),
    ],
    refCountGuardTripped: false,
    totalRefCount: 3,
  ),
);

const String _restoreFileOid = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

final RepoSessionState _restoreFileState = RepoSessionState(
  isOpen: true,
  commitMetaCache: <String, CommitMeta>{
    _restoreFileOid: const CommitMeta(
      oid: _restoreFileOid,
      tree: '',
      parents: <String>[],
      author: Signature(
        name: 'Test',
        email: 'test@example.invalid',
        when: 0,
        tzOffsetMinutes: 0,
      ),
      committer: Signature(
        name: 'Test',
        email: 'test@example.invalid',
        when: 0,
        tzOffsetMinutes: 0,
      ),
      subject: 'Fix lane allocator overflow',
      body: '',
      signedCommit: false,
    ),
  },
);

// Rename branch's own doc comment: RefInfo.upstream keyed alone, deliberately
// not conjoined with hasTrackingInfo -- so a plain upstream string is enough
// here, unlike _rebaseOntoStateWithRemote which goes through
// remoteCounterpartOf() instead.
final RepoSessionState _renameBranchStateWithUpstream = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'feature/lane-allocator',
      fullRef: 'refs/heads/feature/lane-allocator',
      target: 'aaaa',
    ),
    refs: <RefInfo>[
      _trackedLocalRef(
        'feature/lane-allocator',
        upstreamShortName: 'origin/feature/lane-allocator',
        ahead: 2,
      ),
    ],
    refCountGuardTripped: false,
    totalRefCount: 1,
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Widget dialog, {
  String branchName = 'main',
  List<OperationChoice> checkoutChoices = const <OperationChoice>[],
  List<OperationChoice> deleteBranchChoices = const <OperationChoice>[],
  GitError? lastError,
  RepoSessionState? overrideState,
  List<WorkingCopyEntry> workingCopyEntries = const <WorkingCopyEntry>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final RepoSessionState base =
      overrideState ?? (branchName == 'main' ? _state : _stateFor(branchName));
  RepoSessionState seeded = base;
  if (workingCopyEntries.isNotEmpty) {
    seeded = seeded.copyWith(
      workingCopyStatus: WorkingCopyStatus(entries: workingCopyEntries),
    );
  }
  if (checkoutChoices.isNotEmpty) {
    seeded = seeded.copyWith(checkoutChoices: checkoutChoices);
  }
  if (deleteBranchChoices.isNotEmpty) {
    seeded = seeded.copyWith(deleteBranchChoices: deleteBranchChoices);
  }
  if (lastError != null) {
    seeded = seeded.copyWith(lastError: lastError);
  }
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    seeded,
  );

  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(path: '/dialog', builder: (context, state) => dialog),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        repoSessionProvider(_identity).overrideWith((ref) => controller),
      ],
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/dialog');
  await tester.pumpAndSettle();
}

/// Every label, option and hint the dialog draws, in one pass.
void _expectAll(List<String> texts) {
  for (final String text in texts) {
    expect(find.text(text), findsOneWidget, reason: 'missing copy: $text');
  }
}

void main() {
  group('Merge Branch', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const MergeDialogContent(identity: _identity));
      _expectAll(<String>['Merge Branch', 'Merge', 'Cancel']);
    });

    testWidgets('labels, options and hints are Chinese', (tester) async {
      await _pump(tester, const MergeDialogContent(identity: _identity));
      _expectAll(<String>[
        '合入 main',
        '來源分支',
        '只允許 fast-forward',
        'Merge commit（保留分支形狀）',
        'Squash 成一筆',
        'Commit 訊息（可留空）',
        '先 stash 未提交的變更',
      ]);
      expect(
        find.text('Branch to merge from'),
        findsNothing,
        reason: 'an English field label left behind is the miss',
      );
    });

    // The Chinese copy is shorter than the English it replaced, and that
    // alone took this dialog under the shell's height -- reverting the copy
    // as a mutation threw `A RenderFlex overflowed by 11 pixels on the
    // bottom`. Incidental is not fixed: a long branch name wraps 「合入 …」
    // onto a second line and buys the 11px straight back.
    //
    // [FLU-renderflex-non-flex-first]: the Column's children are all
    // non-flex, so nothing inside it can give way. [TEST-canvas-is-800x600]
    // is why this is visible here at all -- the default canvas is the real
    // window's order of size, and GbmDialogShell caps at 560.
    testWidgets('a long branch name does not overflow the shell', (
      tester,
    ) async {
      await _pump(
        tester,
        const MergeDialogContent(identity: _identity),
        branchName: 'feature/lane-allocator-colour-separation-window',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Checkout', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const CheckoutDialogContent(identity: _identity));
      // Title and primary button are the same literal string here, unlike
      // every other dialog in this file -- two matches is the English-stays
      // assertion, not a bug in the fixture.
      expect(find.text('Checkout'), findsNWidgets(2));
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('the search hint and empty message are Chinese', (
      tester,
    ) async {
      await _pump(tester, const CheckoutDialogContent(identity: _identity));
      expect(find.text('可搜尋 branch / tag / commit'), findsOneWidget);
      expect(find.text('Search branches, tags and commits'), findsNothing);
    });

    testWidgets('selecting a remote branch explains the local branch it '
        'creates, in Chinese', (tester) async {
      await _pump(
        tester,
        const CheckoutDialogContent(identity: _identity),
        overrideState: _checkoutStateWithRemote,
      );
      await tester.tap(find.text('origin/wip/askpass'));
      await tester.pump();
      expect(
        find.text('建立本地分支「wip/askpass」，追蹤 origin/wip/askpass。'),
        findsOneWidget,
      );
      expect(find.textContaining('Creates local branch'), findsNothing);
    });

    // Closes [DRIFT-checkout-dialog-mock-delta]: DLGS's Checkout entry draws
    // a read-only 目前 row (`main · 有25 項未提交變更`) ahead of the
    // radio-on/radio pair, so the row is asserted on a clean tree first
    // (bare "目前 main", no count) and again once dirty.
    testWidgets('the current-branch row shows with no count on a clean tree', (
      tester,
    ) async {
      await _pump(tester, const CheckoutDialogContent(identity: _identity));
      expect(find.text('目前 main'), findsOneWidget);
    });

    testWidgets(
      'the current-branch row appends the pending count, DLGS-quoted, '
      'once dirty',
      (tester) async {
        await _pump(
          tester,
          const CheckoutDialogContent(identity: _identity),
          workingCopyEntries: <WorkingCopyEntry>[_wcEntry('a.txt')],
        );
        expect(find.text('目前 main · 有1 項未提交變更'), findsOneWidget);
      },
    );

    testWidgets('the stash-choice radios are absent on a clean tree', (
      tester,
    ) async {
      await _pump(tester, const CheckoutDialogContent(identity: _identity));
      expect(find.text('帶著變更切過去'), findsNothing);
      expect(find.text('先 stash，切完不自動還原'), findsNothing);
    });

    testWidgets(
      'the stash-choice radios are Chinese and quoted from DLGS, once dirty',
      (tester) async {
        await _pump(
          tester,
          const CheckoutDialogContent(identity: _identity),
          workingCopyEntries: <WorkingCopyEntry>[_wcEntry('a.txt')],
        );
        expect(find.text('帶著變更切過去'), findsOneWidget);
        expect(find.text('先 stash，切完不自動還原'), findsOneWidget);
        expect(find.textContaining('uncommitted changes first'), findsNothing);
        expect(find.text('先 stash 未提交的變更'), findsNothing);
      },
    );

    testWidgets('carrying the changes across is the default radio', (
      tester,
    ) async {
      await _pump(
        tester,
        const CheckoutDialogContent(identity: _identity),
        workingCopyEntries: <WorkingCopyEntry>[_wcEntry('a.txt')],
      );
      final RadioListTile<bool> carryOver = tester.widget(
        find.widgetWithText(RadioListTile<bool>, '帶著變更切過去'),
      );
      expect(carryOver.value, isFalse);
      final RadioGroup<bool> group = tester.widget(
        find.byType(RadioGroup<bool>),
      );
      expect(group.groupValue, isFalse);
    });

    testWidgets('does not overflow the shell', (tester) async {
      await _pump(
        tester,
        const CheckoutDialogContent(identity: _identity),
        workingCopyEntries: <WorkingCopyEntry>[
          _wcEntry('a.txt'),
          _wcEntry('b.txt'),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Rebase onto', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const RebaseOntoDialogContent(identity: _identity));
      _expectAll(<String>['Rebase', 'Cancel', 'Start rebase']);
    });

    testWidgets('the lead-in, the dropdown hint and the explanation are '
        'Chinese', (tester) async {
      await _pump(tester, const RebaseOntoDialogContent(identity: _identity));
      expect(find.text('重新安置 main 到：'), findsOneWidget);
      expect(find.text('基於'), findsOneWidget);
      expect(find.textContaining('Rebase 會重寫 main 的 commit'), findsOneWidget);
      expect(find.textContaining('Replay the commits'), findsNothing);
      expect(find.text('Branch to rebase onto'), findsNothing);
    });

    testWidgets('the stash-first checkbox is Chinese', (tester) async {
      await _pump(
        tester,
        const RebaseOntoDialogContent(identity: _identity),
        workingCopyEntries: <WorkingCopyEntry>[_wcEntry('a.txt')],
      );
      expect(find.text('先 stash 未提交的變更'), findsOneWidget);
      expect(find.text('1 個檔案有未提交的變更。'), findsOneWidget);
      expect(find.textContaining('uncommitted changes first'), findsNothing);
    });

    // Closes [DRIFT-rebase-onto-missing-capi-flags]'s checkbox half: DLGS's
    // Rebase onto entry has chk-on 「保留 merge commit（--rebase-merges）」
    // and chk 「自動 squash 標記過的 fixup commit」, quoted verbatim.
    testWidgets('the rebase-merges and autosquash checkboxes are Chinese '
        'and quoted from DLGS', (tester) async {
      await _pump(tester, const RebaseOntoDialogContent(identity: _identity));
      expect(find.text('保留 merge commit（--rebase-merges）'), findsOneWidget);
      expect(find.text('自動 squash 標記過的 fixup commit'), findsOneWidget);
    });

    testWidgets('rebase-merges defaults on (chk-on) and autosquash defaults '
        'off (chk)', (tester) async {
      await _pump(tester, const RebaseOntoDialogContent(identity: _identity));
      final CheckboxListTile rebaseMerges = tester.widget(
        find.widgetWithText(
          CheckboxListTile,
          '保留 merge commit（--rebase-merges）',
        ),
      );
      expect(rebaseMerges.value, isTrue);
      final CheckboxListTile autosquash = tester.widget(
        find.widgetWithText(CheckboxListTile, '自動 squash 標記過的 fixup commit'),
      );
      expect(autosquash.value, isFalse);
    });

    // Dispatch itself (does Start rebase actually pass these two values to
    // startRebase()) is rebase_onto_dialog_test.dart's job, not this file's
    // -- this file's own header states its scope is copy, held against the
    // spec's per-element language rule.

    // Closes the pin's warn-banner half. remoteCounterpartOf() is the same
    // single source delete_branch_dialog.dart's own doc comment names traps
    // #2 and #3 for -- hasTrackingInfo is empty for a branch exactly in
    // sync, and upstream alone misses a `push origin HEAD` branch with no
    // tracking config -- so the predicate is never re-derived here.
    testWidgets(
      'the already-pushed warn banner is absent with no remote counterpart',
      (tester) async {
        await _pump(tester, const RebaseOntoDialogContent(identity: _identity));
        expect(find.textContaining('此分支已 push'), findsNothing);
      },
    );

    testWidgets(
      'the already-pushed warn banner is Chinese and quoted from DLGS, once '
      'the current branch has a remote counterpart',
      (tester) async {
        await _pump(
          tester,
          const RebaseOntoDialogContent(identity: _identity),
          overrideState: _rebaseOntoStateWithRemote,
        );
        expect(
          find.text('此分支已 push。rebase 後需 force push，共作者需重新對齊。'),
          findsOneWidget,
        );
      },
    );

    testWidgets('does not overflow the shell', (tester) async {
      await _pump(
        tester,
        const RebaseOntoDialogContent(identity: _identity),
        workingCopyEntries: <WorkingCopyEntry>[
          _wcEntry('a.txt'),
          _wcEntry('b.txt'),
        ],
        overrideState: _rebaseOntoStateWithRemote.copyWith(
          workingCopyStatus: WorkingCopyStatus(
            entries: <WorkingCopyEntry>[_wcEntry('a.txt'), _wcEntry('b.txt')],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('New Branch', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const NewBranchDialogContent(identity: _identity));
      _expectAll(<String>['New Branch', 'Cancel', 'Create branch']);
    });

    testWidgets('labels, the section header and the search hint are '
        'Chinese', (tester) async {
      await _pump(tester, const NewBranchDialogContent(identity: _identity));
      _expectAll(<String>[
        '名稱',
        '從哪裡分出',
        '可搜尋 branch / tag / commit',
        '建立後直接 checkout',
      ]);
      expect(find.text('Branch name'), findsNothing);
      expect(find.text('START POINT'), findsNothing);
      expect(find.text('Search branches, tags and commits'), findsNothing);
      expect(find.text('Check out the new branch immediately'), findsNothing);
    });

    testWidgets(
      'the push-after-create option is Chinese with exactly one remote',
      (tester) async {
        await _pump(
          tester,
          const NewBranchDialogContent(identity: _identity),
          overrideState: _newBranchStateWithRemote,
        );
        expect(find.text('同時 push 並設為 upstream'), findsOneWidget);
        expect(find.text('會推送到 origin。'), findsOneWidget);
        expect(find.text('Push and set as upstream'), findsNothing);
      },
    );
  });

  group('Delete Branch', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(
        tester,
        const DeleteBranchDialogContent(
          identity: _identity,
          branchName: 'feature/lane-allocator',
        ),
      );
      _expectAll(<String>['Delete Branch', 'Delete branch', 'Cancel']);
    });

    testWidgets('the confirmation and no-upstream note are Chinese', (
      tester,
    ) async {
      await _pump(
        tester,
        const DeleteBranchDialogContent(
          identity: _identity,
          branchName: 'feature/lane-allocator',
        ),
      );
      expect(find.textContaining('刪除本地分支'), findsOneWidget);
      expect(find.text('這個分支沒有 upstream，只存在於這台機器上。'), findsOneWidget);
      expect(find.text('如果分支還沒完全合併，git 會拒絕，並提供強制刪除的選項。'), findsOneWidget);
      expect(find.textContaining('Delete the local branch'), findsNothing);
    });

    testWidgets('the also-delete-remote checkbox is Chinese', (tester) async {
      await _pump(
        tester,
        const DeleteBranchDialogContent(
          identity: _identity,
          branchName: 'wip/askpass',
        ),
        overrideState: _deleteBranchStateWithRemote,
      );
      expect(find.text('同時刪除 origin 上的 wip/askpass'), findsOneWidget);
      expect(find.text('其他人要等到下次 fetch 才會看不到這個分支。'), findsOneWidget);
    });

    testWidgets('the branch picker hint and prompt are Chinese', (
      tester,
    ) async {
      await _pump(tester, const DeleteBranchDialogContent(identity: _identity));
      expect(find.text('要刪除的分支'), findsOneWidget);
      expect(find.text('選擇要刪除的分支。'), findsOneWidget);
      expect(find.text('Branch to delete'), findsNothing);
    });

    testWidgets('does not overflow the shell', (tester) async {
      await _pump(
        tester,
        const DeleteBranchDialogContent(
          identity: _identity,
          branchName: 'wip/askpass',
        ),
        overrideState: _deleteBranchStateWithRemote,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Delete Branches', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(
        tester,
        DeleteBranchesDialogContent(
          identity: _identity,
          names: const <String>['untracked/x', 'tracked/y'],
        ),
        overrideState: _deleteBranchesState,
      );
      expect(find.text('Delete 2 branches'), findsNWidgets(2));
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('the section titles, details and checkboxes are Chinese', (
      tester,
    ) async {
      await _pump(
        tester,
        DeleteBranchesDialogContent(
          identity: _identity,
          names: const <String>['untracked/x', 'tracked/y'],
        ),
        overrideState: _deleteBranchesState,
      );
      expect(find.text('本地分支'), findsOneWidget);
      expect(find.text('遠端分支'), findsOneWidget);
      expect(find.text('沒有 upstream，尚未推送過'), findsOneWidget);
      expect(find.text('2 個未推送的 commit'), findsOneWidget);
      expect(find.text('同時刪除遠端分支'), findsOneWidget);
      expect(find.text('即使尚未完全合併也刪除'), findsOneWidget);
      expect(find.text('Local branches'), findsNothing);
      expect(find.text('Also delete on the remote'), findsNothing);
    });

    testWidgets('does not overflow the shell', (tester) async {
      await _pump(
        tester,
        DeleteBranchesDialogContent(
          identity: _identity,
          names: const <String>['untracked/x', 'tracked/y'],
        ),
        overrideState: _deleteBranchesState,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Cherry-pick Commits', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const CherryPickDialogContent(identity: _identity));
      _expectAll(<String>['Cherry-pick Commits', 'Cherry-pick', 'Cancel']);
    });

    testWidgets('labels, options and hints are Chinese', (tester) async {
      await _pump(tester, const CherryPickDialogContent(identity: _identity));
      _expectAll(<String>[
        '套用這些 commit（依序）',
        '以空白或換行分隔，舊的在前',
        '不自動 commit（-n，套完停在工作區）',
        '先 stash 未提交的變更',
      ]);
    });
  });

  group('Create Tag', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const CreateTagDialogContent(identity: _identity));
      _expectAll(<String>['Create Tag', 'Create', 'Cancel']);
    });

    testWidgets('labels, options and hints are Chinese', (tester) async {
      await _pump(tester, const CreateTagDialogContent(identity: _identity));
      // The spec draws annotated/lightweight as a radio pair; this dialog
      // derives it from whether the message is empty, so the spec's hint
      // 「lightweight 時此欄停用並調暗」 describes a control that is not
      // here. The copy says what this dialog actually does instead.
      _expectAll(<String>[
        '名稱',
        '指向',
        '留空表示 HEAD',
        '訊息',
        '留空則建立 lightweight tag',
        '覆蓋同名的既有 tag（-f）',
      ]);
    });

    testWidgets('does not overflow the shell', (tester) async {
      await _pump(tester, const CreateTagDialogContent(identity: _identity));
      expect(tester.takeException(), isNull);
    });
  });

  group('Clean Untracked Files', () {
    testWidgets('title stays English', (tester) async {
      await _pump(
        tester,
        const CleanUntrackedDialogContent(identity: _identity),
      );
      _expectAll(<String>['Clean Untracked Files', 'Cancel']);
    });

    testWidgets('labels, options and the spec warning are Chinese', (
      tester,
    ) async {
      await _pump(
        tester,
        const CleanUntrackedDialogContent(identity: _identity),
      );
      _expectAll(<String>[
        '包含被 gitignore 忽略的檔案（-x）',
        '沒有可清除的檔案',
        // Stated by the spec and previously said nowhere in the app. It is
        // the half a user cannot infer from a Delete button.
        '這是 git clean，直接從磁碟刪檔，不進回收筒。',
      ]);
    });

    testWidgets('does not overflow the shell', (tester) async {
      await _pump(
        tester,
        const CleanUntrackedDialogContent(identity: _identity),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Undo Last Operation', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const UndoLastDialogContent(identity: _identity));
      _expectAll(<String>['Undo Last Operation', 'Undo', 'Cancel']);
    });

    testWidgets('the empty state is Chinese', (tester) async {
      await _pump(tester, const UndoLastDialogContent(identity: _identity));
      _expectAll(<String>['目前沒有可以復原的動作']);
    });
  });

  group('Reset Branch', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const ResetBranchDialogContent(identity: _identity));
      _expectAll(<String>['Reset Branch', 'Reset', 'Cancel']);
    });

    testWidgets('labels, options and hints are Chinese', (tester) async {
      await _pump(tester, const ResetBranchDialogContent(identity: _identity));
      _expectAll(<String>[
        '重設到',
        'branch、tag 或 commit',
        'Soft — 保留檔案與 stage',
        'Mixed — 保留檔案，取消 stage',
        'Hard — 丟掉檔案變更',
      ]);
    });

    testWidgets('does not overflow the shell', (tester) async {
      await _pump(tester, const ResetBranchDialogContent(identity: _identity));
      expect(tester.takeException(), isNull);
    });
  });

  group('Force Push', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const ForcePushDialogContent(identity: _identity));
      _expectAll(<String>['Force Push', 'Force push', 'Cancel']);
    });

    testWidgets('the body, the note and the opt-out are Chinese', (
      tester,
    ) async {
      await _pump(tester, const ForcePushDialogContent(identity: _identity));
      _expectAll(<String>['不會覆蓋遠端的任何 commit。', '不要再問']);
      expect(
        find.textContaining('使用 --force-with-lease 推送'),
        findsOneWidget,
        reason: 'the --force-with-lease explanation is a note, so Chinese',
      );
      expect(find.textContaining('has diverged from'), findsNothing);
    });
  });

  group('Delete Remote Branch', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(
        tester,
        const DeleteRemoteBranchDialogContent(
          identity: _identity,
          remote: 'origin',
          branch: 'wip/askpass',
        ),
      );
      _expectAll(<String>[
        'Delete Remote Branch',
        'Delete remote branch',
        'Cancel',
      ]);
    });

    testWidgets('the notes are Chinese', (tester) async {
      await _pump(
        tester,
        const DeleteRemoteBranchDialogContent(
          identity: _identity,
          remote: 'origin',
          branch: 'wip/askpass',
        ),
      );
      _expectAll(<String>['同名的本地分支不會被動到。', '其他人要等到下次 fetch 才會看不到這個分支。']);
      // The heading is a RichText of five spans, so find.text cannot see it.
      expect(
        find.textContaining('刪除分支'),
        findsOneWidget,
        reason: 'the heading spans were reordered, not just translated',
      );
    });
  });

  group('Prune Remote Branches', () {
    testWidgets('title stays English', (tester) async {
      await _pump(
        tester,
        const PruneRemoteBranchesDialogContent(identity: _identity),
      );
      _expectAll(<String>['Prune Remote Branches', 'Cancel']);
    });

    testWidgets('says what it does and does not prune', (tester) async {
      await _pump(
        tester,
        const PruneRemoteBranchesDialogContent(identity: _identity),
      );
      // The spec asks for this by position as well as by content: 「標題列下
      // 方一行寫明這件事」. It draws the distinction that is the whole risk
      // of the dialog, and the app stated it nowhere.
      _expectAll(<String>[
        '只清除遠端已經不存在的 tracking ref，不會刪掉遠端分支，也不會動到本地分支。',
        '沒有設定任何 remote',
      ]);
    });
  });

  group('Credentials Required', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const CredentialDialogContent(identity: _identity));
      _expectAll(<String>['Credentials Required', 'Submit', 'Cancel']);
    });

    testWidgets('the field label is the spec\'s', (tester) async {
      await _pump(tester, const CredentialDialogContent(identity: _identity));
      // Not obscured with no prompt, so this is the account field.
      _expectAll(<String>['帳號']);
      expect(find.text('Username'), findsNothing);
    });
  });

  // Added only after a mutation check: reverting this dialog's copy reddened
  // *nothing*, because the batch that changed it shipped without a test for
  // it. A copy change no test can disagree with is not a covered change.
  group('Checkout Blocked', () {
    testWidgets(
      'the explanation is Chinese, the choice buttons are not, and Cancel '
      'is not drawn twice',
      (tester) async {
        // The wire carries only `kind`/`destructive` -- button label and
        // body-list explanation are composed in Dart from `choice.kind`
        // (recovery_choice_copy.dart). There is no `label`/`explanation`
        // field left to construct a decoy string with; that guarantee used
        // to be asserted here by checking a fake wire string was never
        // drawn, and is now enforced by the compiler instead.
        await _pump(
          tester,
          const CheckoutRecoveryDialogContent(identity: _identity),
          checkoutChoices: const <OperationChoice>[
            OperationChoice(
              kind: OperationChoiceKind.stashAndRetry,
              destructive: false,
            ),
            // Included specifically to pin the duplicate-Cancel fix: `abort`
            // choices used to be filtered out of the action-bar buttons but
            // not out of this body list, so this same choice re-drew
            // "Cancel" a second time next to the hardcoded action button.
            OperationChoice(
              kind: OperationChoiceKind.abort,
              destructive: false,
            ),
          ],
        );

        _expectAll(<String>['Checkout Blocked', '這次 checkout 得先把未提交的變更挪開。']);
        // findsWidgets, not findsOneWidget: this dialog draws each non-abort
        // choice twice -- once as an action button and once as a row in the
        // body list that carries its explanation.
        expect(find.text('Stash and checkout'), findsWidgets);
        expect(find.text('你的變更會先存進 stash，之後可以再取回來。'), findsOneWidget);
        // Exactly one "Cancel": the hardcoded action-bar button. The
        // `abort` choice above must not add a second one anywhere.
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets('a lock/sequencer refusal (retry/removeLock choices, no '
        'stashAndRetry/forceDiscard) shows core\'s own message instead of the '
        "dirty-work-tree sentence", (tester) async {
      // checkoutChoices populated this way -- Retry + RemoveLock, no
      // stashAndRetry/forceDiscard -- is what OperationRunner::preflight()
      // produces for an index.lock refusal, never CheckoutOp.cpp's own
      // dirty-tree path. The dirty-tree sentence above ("這次 checkout 得先
      // 把未提交的變更挪開。") would be actively wrong here: nothing about
      // this refusal has anything to do with uncommitted changes.
      await _pump(
        tester,
        const CheckoutRecoveryDialogContent(identity: _identity),
        checkoutChoices: const <OperationChoice>[
          OperationChoice(kind: OperationChoiceKind.retry, destructive: false),
          OperationChoice(
            kind: OperationChoiceKind.removeLock,
            destructive: true,
          ),
        ],
        lastError: const GitError(
          code: 0,
          codeName: 'LockHeld',
          message:
              'Another Git process appears to be running in this '
              'repository',
          detail: '',
          argv: <String>[],
          exitCode: 1,
        ),
      );

      expect(
        find.text(
          'Another Git process appears to be running in this repository',
        ),
        findsOneWidget,
      );
      expect(find.text('這次 checkout 得先把未提交的變更挪開。'), findsNothing);
      expect(find.text('Retry'), findsWidgets);
      expect(find.text('Remove index.lock'), findsWidgets);
    });
  });

  group('Delete Blocked', () {
    testWidgets(
      'the forDeleteBranch explanation is drawn, and it differs from the '
      "checkout side's",
      (tester) async {
        // Same composed-not-wire shape as Checkout Blocked above, but this
        // is the one place `recoveryChoiceExplanation(forDeleteBranch:
        // true)`'s `forceDiscard` arm ("強制刪除；之後只能透過 reflog…") was
        // ever asserted -- without this group a mutation of that arm alone
        // (leaving the `forDeleteBranch: false` arm untouched) stayed fully
        // green, because `dialog_copy_test.dart`'s only prior coverage of
        // `recovery_choice_copy.dart` was the checkout side.
        await _pump(
          tester,
          const DeleteBranchRecoveryDialogContent(identity: _identity),
          deleteBranchChoices: const <OperationChoice>[
            OperationChoice(
              kind: OperationChoiceKind.forceDiscard,
              destructive: true,
            ),
          ],
        );

        _expectAll(<String>['Delete Blocked']);
        expect(find.text('Delete anyway'), findsWidgets);
        expect(
          find.text('強制刪除；之後只能透過 reflog 找回這個分支上的 commit。'),
          findsOneWidget,
        );
        // Not the checkout side's forceDiscard wording -- confirms the two
        // `forDeleteBranch` arms are genuinely distinct, not one string
        // reused for both.
        expect(find.text('未提交的變更會被永久丟棄，無法復原。'), findsNothing);
      },
    );
  });

  // The reducer-level test pinning that a preflight-shaped outcome publishes
  // checkoutChoices and lastError together lives in
  // repo_session_operation_outcome_test.dart, next to the other
  // _handleOperationOutcome coverage -- see that file's "arrive together"
  // test.

  group('Stash Changes', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const StashChangesDialogContent(identity: _identity));
      _expectAll(<String>['Stash Changes', 'Stash', 'Cancel']);
    });

    testWidgets('labels, options and hints are Chinese', (tester) async {
      await _pump(tester, const StashChangesDialogContent(identity: _identity));
      _expectAll(<String>[
        '訊息',
        '空白時使用預設的 WIP on <branch>',
        '包含 untracked 檔案',
        '保留已 stage 的內容在工作區',
      ]);
      expect(
        find.text('Message (optional)'),
        findsNothing,
        reason: '「(optional)」 moved into the hint, it did not stay',
      );
    });
  });

  group('Discard Changes', () {
    testWidgets('title and Cancel stay English', (tester) async {
      await _pump(
        tester,
        DiscardChangesDialogContent(
          identity: _identity,
          request: const DiscardChangesRequest.wholeFiles(<String>['a.txt']),
        ),
        workingCopyEntries: <WorkingCopyEntry>[_wcEntry('a.txt')],
      );
      expect(find.text('Discard Changes'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('the list lead-in is Chinese and quoted from DLGS, and the '
        'primary button names the single file rather than a count', (
      tester,
    ) async {
      await _pump(
        tester,
        DiscardChangesDialogContent(
          identity: _identity,
          request: const DiscardChangesRequest.wholeFiles(<String>['a.txt']),
        ),
        workingCopyEntries: <WorkingCopyEntry>[_wcEntry('a.txt')],
      );
      expect(find.text('丟掉這些變更：'), findsOneWidget);
      expect(
        find.textContaining('uncommitted changes in these files'),
        findsNothing,
      );
      // Closes DLGS's note: 主按鈕寫出實際數量；兩個檔案以下改成寫檔名.
      expect(find.text('Discard a.txt'), findsOneWidget);
      expect(find.text('Discard changes'), findsNothing);
    });

    testWidgets('the primary button joins two filenames rather than '
        'showing a count', (tester) async {
      await _pump(
        tester,
        DiscardChangesDialogContent(
          identity: _identity,
          request: const DiscardChangesRequest.wholeFiles(<String>[
            'a.txt',
            'b/c.txt',
          ]),
        ),
        workingCopyEntries: <WorkingCopyEntry>[
          _wcEntry('a.txt'),
          _wcEntry('b/c.txt'),
        ],
      );
      expect(find.text('Discard a.txt, c.txt'), findsOneWidget);
      expect(find.text('Discard 2 files'), findsNothing);
    });

    testWidgets('the warn text is Chinese and quoted verbatim from DLGS', (
      tester,
    ) async {
      await _pump(
        tester,
        DiscardChangesDialogContent(
          identity: _identity,
          request: const DiscardChangesRequest.wholeFiles(<String>['a.txt']),
        ),
        workingCopyEntries: <WorkingCopyEntry>[_wcEntry('a.txt')],
      );
      expect(find.text('這些變更不進 stash、也不在 reflog，丟掉就沒了。'), findsOneWidget);
      expect(find.textContaining('This cannot be undone'), findsNothing);
    });

    testWidgets('does not overflow the shell', (tester) async {
      final WorkingCopyEntry untrackedEntry = WorkingCopyEntry(
        path: 'new.txt',
        oldPath: '',
        untracked: true,
        staged: false,
        indexStatus: FileChangeKind.added,
        hasUnstagedChange: true,
        worktreeStatus: FileChangeKind.added,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      );
      await _pump(
        tester,
        DiscardChangesDialogContent(
          identity: _identity,
          request: const DiscardChangesRequest.wholeFiles(<String>[
            'a.txt',
            'b/c.txt',
            'new.txt',
          ]),
        ),
        workingCopyEntries: <WorkingCopyEntry>[
          _wcEntry('a.txt'),
          _wcEntry('b/c.txt'),
          untrackedEntry,
        ],
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Restore File', () {
    testWidgets('title and buttons stay English', (tester) async {
      await _pump(
        tester,
        const RestoreFileDialogContent(
          identity: _identity,
          path: 'lib/graph/lane_allocator.dart',
          oid: _restoreFileOid,
        ),
        overrideState: _restoreFileState,
      );
      _expectAll(<String>['Restore File', 'Cancel', 'Restore and stage']);
      expect(find.text('Restore'), findsOneWidget);
    });

    testWidgets('the two ro labels are Chinese and quoted from DLGS', (
      tester,
    ) async {
      await _pump(
        tester,
        const RestoreFileDialogContent(
          identity: _identity,
          path: 'lib/graph/lane_allocator.dart',
          oid: _restoreFileOid,
        ),
        overrideState: _restoreFileState,
      );
      expect(find.text('檔案'), findsOneWidget);
      expect(find.text('還原成'), findsOneWidget);
      expect(find.text('RESTORE FROM'), findsNothing);
    });

    testWidgets('the working-copy line is Chinese and matches the boolean '
        'this dialog actually has, on a clean file', (tester) async {
      await _pump(
        tester,
        const RestoreFileDialogContent(
          identity: _identity,
          path: 'lib/graph/lane_allocator.dart',
          oid: _restoreFileOid,
        ),
        overrideState: _restoreFileState,
      );
      expect(find.text('工作區內這個檔案的版本將被取代。'), findsOneWidget);
      expect(find.textContaining('The working copy version'), findsNothing);
    });

    testWidgets('the working-copy line is Chinese once the file is dirty', (
      tester,
    ) async {
      await _pump(
        tester,
        const RestoreFileDialogContent(
          identity: _identity,
          path: 'lib/graph/lane_allocator.dart',
          oid: _restoreFileOid,
        ),
        overrideState: _restoreFileState,
        workingCopyEntries: <WorkingCopyEntry>[
          _wcEntry('lib/graph/lane_allocator.dart'),
        ],
      );
      expect(find.text('此檔在工作區有未提交的變更，會被覆蓋且無法復原。'), findsOneWidget);
      expect(find.textContaining('uncommitted changes'), findsNothing);
    });

    testWidgets('the closing note is Chinese', (tester) async {
      await _pump(
        tester,
        const RestoreFileDialogContent(
          identity: _identity,
          path: 'lib/graph/lane_allocator.dart',
          oid: _restoreFileOid,
        ),
        overrideState: _restoreFileState,
      );
      expect(
        find.text('不會建立新的 commit。還原後的檔案會像一般工作區變更一樣，之後仍可以再 discard。'),
        findsOneWidget,
      );
      expect(find.textContaining('No commit is created'), findsNothing);
    });

    testWidgets('does not overflow the shell', (tester) async {
      await _pump(
        tester,
        const RestoreFileDialogContent(
          identity: _identity,
          path: 'lib/graph/lane_allocator.dart',
          oid: _restoreFileOid,
        ),
        overrideState: _restoreFileState,
        workingCopyEntries: <WorkingCopyEntry>[
          _wcEntry('lib/graph/lane_allocator.dart'),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Rename Branch', () {
    testWidgets('title and buttons stay English', (tester) async {
      await _pump(
        tester,
        const RenameBranchDialogContent(identity: _identity),
        overrideState: _renameBranchStateWithUpstream,
      );
      _expectAll(<String>['Rename Branch', 'Cancel', 'Rename']);
    });

    testWidgets('the two ro labels and the field hint are Chinese, quoted '
        'from RENAMEVALID / P13-A', (tester) async {
      await _pump(
        tester,
        const RenameBranchDialogContent(identity: _identity),
        overrideState: _renameBranchStateWithUpstream,
      );
      expect(find.text('目前名稱'), findsOneWidget);
      expect(find.text('新名稱'), findsOneWidget);
      expect(find.text('新的分支名稱'), findsOneWidget);
      expect(find.text('Current name'), findsNothing);
      expect(find.text('New name'), findsNothing);
    });

    testWidgets('a duplicate name is quoted verbatim from RENAMEVALID row 1', (
      tester,
    ) async {
      final RepoSessionState stateWithMain = RepoSessionState(
        isOpen: true,
        refs: RefSnapshot(
          head: const HeadInfo(
            kind: HeadKind.branch,
            branchName: 'feature/lane-allocator',
            fullRef: 'refs/heads/feature/lane-allocator',
            target: 'aaaa',
          ),
          refs: <RefInfo>[
            _trackedLocalRef(
              'feature/lane-allocator',
              upstreamShortName: 'origin/feature/lane-allocator',
              ahead: 2,
            ),
            _ref('main'),
          ],
          refCountGuardTripped: false,
          totalRefCount: 2,
        ),
      );
      await _pump(
        tester,
        const RenameBranchDialogContent(identity: _identity),
        overrideState: stateWithMain,
      );
      await tester.enterText(find.byType(TextField), 'main');
      await tester.pumpAndSettle();
      expect(find.text('已存在「main」'), findsOneWidget);
      expect(find.textContaining('already exists'), findsNothing);
    });

    testWidgets('the availability line is Chinese', (tester) async {
      await _pump(
        tester,
        const RenameBranchDialogContent(identity: _identity),
        overrideState: _renameBranchStateWithUpstream,
      );
      await tester.enterText(find.byType(TextField), 'feature/lane-v2');
      await tester.pumpAndSettle();
      expect(find.text('可以使用 — 沒有同名的分支。'), findsOneWidget);
    });

    testWidgets('the remote-handling section, its two radio options and the '
        'default warning are Chinese, quoted from the P13-A mock', (
      tester,
    ) async {
      await _pump(
        tester,
        const RenameBranchDialogContent(identity: _identity),
        overrideState: _renameBranchStateWithUpstream,
      );
      expect(find.text('遠端連帶處理'), findsOneWidget);
      expect(find.text('一併更名遠端分支'), findsOneWidget);
      expect(
        find.text('push 新名稱，再刪除 origin/feature/lane-allocator'),
        findsOneWidget,
      );
      expect(find.text('只改本地，保留遠端舊分支'), findsOneWidget);
      expect(find.text('新分支的 upstream 會清空'), findsOneWidget);
      expect(find.textContaining('遠端更名 = delete + push'), findsOneWidget);
      expect(find.textContaining('有 2 個未 push 的 commit'), findsOneWidget);
      expect(find.text('Remote handling'), findsNothing);
    });

    testWidgets('choosing local-only shows RENAMEVALID row 4\'s hint instead', (
      tester,
    ) async {
      await _pump(
        tester,
        const RenameBranchDialogContent(identity: _identity),
        overrideState: _renameBranchStateWithUpstream,
      );
      await tester.tap(find.text('只改本地，保留遠端舊分支'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('新分支不會有 upstream，之後需重新 push -u'),
        findsOneWidget,
      );
      expect(find.textContaining('遠端更名 = delete + push'), findsNothing);
    });

    testWidgets('mid-conflict the refusal message is Chinese, quoted from '
        'RENAMEVALID row 5', (tester) async {
      await _pump(
        tester,
        const RenameBranchDialogContent(identity: _identity),
        overrideState: _renameBranchStateWithUpstream.copyWith(
          repoState: const RepoState(
            flags: RepoStateFlags.rebaseMerge,
            isClean: false,
            isSequencerOperation: true,
            rebaseStep: 1,
            rebaseTotal: 3,
            rebaseOntoLabel: '',
            indexLocked: false,
            indexLockAgeSeconds: null,
            describe: '',
          ),
        ),
      );
      expect(find.text('先完成或中止進行中的作業'), findsOneWidget);
      expect(find.textContaining('Finish or abort'), findsNothing);
    });
  });

  group('Repository Settings', () {
    testWidgets('title, Close and the four tab names stay English -- DIALOGS '
        'quotes them in English inside its own Chinese sentence', (
      tester,
    ) async {
      await _pump(
        tester,
        const RepositorySettingsDialogContent(identity: _identity),
      );
      _expectAll(<String>[
        'Repository Settings',
        'Close',
        'General',
        'Remotes',
        'Identity',
        'Performance',
      ]);
    });

    testWidgets('the General tab section labels are Chinese', (tester) async {
      await _pump(
        tester,
        const RepositorySettingsDialogContent(identity: _identity),
      );
      expect(find.text('位置'), findsOneWidget);
      expect(find.text('維護'), findsOneWidget);
      expect(find.text('LOCATION'), findsNothing);
      expect(find.text('MAINTENANCE'), findsNothing);
    });

    testWidgets('the Remotes tab is Chinese with no remotes configured', (
      tester,
    ) async {
      await _pump(
        tester,
        const RepositorySettingsDialogContent(identity: _identity),
      );
      await tester.tap(find.text('Remotes'));
      await tester.pumpAndSettle();
      expect(find.text('遠端'), findsOneWidget);
      expect(find.text('這個 repository 沒有 remote。'), findsOneWidget);
      expect(find.text('This repository has no remotes.'), findsNothing);
    });

    testWidgets('a remote with a distinct push URL gets a Chinese "推送" '
        'label', (tester) async {
      await _pump(
        tester,
        const RepositorySettingsDialogContent(identity: _identity),
        overrideState: _state.copyWith(
          remotes: const <RemoteInfo>[
            RemoteInfo(
              name: 'origin',
              fetchUrl: 'https://example.com/fetch.git',
              pushUrl: 'https://example.com/push.git',
            ),
          ],
        ),
      );
      await tester.tap(find.text('Remotes'));
      await tester.pumpAndSettle();
      expect(find.text('推送：https://example.com/push.git'), findsOneWidget);
      expect(find.textContaining('push: '), findsNothing);
    });

    testWidgets('the Identity tab labels are Chinese', (tester) async {
      await _pump(
        tester,
        const RepositorySettingsDialogContent(identity: _identity),
      );
      await tester.tap(find.text('Identity'));
      await tester.pumpAndSettle();
      expect(find.text('GIT 身份'), findsOneWidget);
      expect(find.text('名稱（僅限此 repository）'), findsOneWidget);
      expect(find.text('Email（僅限此 repository）'), findsOneWidget);
      expect(
        find.textContaining('Effective for new commits here'),
        findsNothing,
      );
      expect(find.text('Name (this repository only)'), findsNothing);
    });

    testWidgets('the Performance tab is Chinese, with commit-graph kept '
        'untranslated as a git term', (tester) async {
      await _pump(
        tester,
        const RepositorySettingsDialogContent(identity: _identity),
      );
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.text('COMMIT-GRAPH'), findsOneWidget);
      expect(
        find.text('commit-graph 可以加快大型 repository 讀取歷史的速度。'),
        findsOneWidget,
      );
      expect(find.text('歷史'), findsOneWidget);
      expect(find.textContaining('A commit-graph can speed up'), findsNothing);
    });
  });
}
