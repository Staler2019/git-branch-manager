import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';

import '../../support/pump_app.dart';

/// SidebarPanel also watches [repoSessionProvider] (for its STASH section).
/// [RepoSessionController]'s constructor unconditionally opens a real FFI
/// session, so `repoSessionProvider` must be overridden -- but Riverpod
/// requires the override closure to return the exact declared type
/// (`RepoSessionController`), not a duck-typed `StateNotifier`. So this
/// constructs a real controller with a fake [GbmBindings] whose
/// `sessionOpen` returns `nullptr`: `RepoSessionController._open()` treats a
/// null session as "open failed" and returns immediately, before touching
/// anything else on `_bindings` or `_recents`.
class _FakeGbmBindings implements GbmBindings {
  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          nullptr;

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => 0;

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not implemented for testing');
}

class _FakeRecentsRepository implements RecentsRepository {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not implemented for testing');
}

final _testIdentity = RepoIdentity.forWorkDir('/test/repo');

final _testBranches = <RefInfo>[
  // Main branch (HEAD)
  RefInfo(
    fullName: 'refs/heads/main',
    shortName: 'main',
    kind: RefKind.localBranch,
    target: 'abc123',
    upstream: 'origin/main',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: true,
    isGone: false,
    isHead: true,
    isSymbolic: true,
    worktreePath: '',
  ),
  // Active branch (not gone)
  RefInfo(
    fullName: 'refs/heads/feature/auth',
    shortName: 'feature/auth',
    kind: RefKind.localBranch,
    target: 'def456',
    upstream: 'origin/feature/auth',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: true,
    isGone: false,
    isHead: false,
    isSymbolic: true,
    worktreePath: '',
  ),
  // Gone branch that WILL be hidden by filter
  RefInfo(
    fullName: 'refs/heads/feature/old-feature',
    shortName: 'feature/old-feature',
    kind: RefKind.localBranch,
    target: 'ghi789',
    upstream: 'origin/feature/old-feature',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: true,
    isGone: true,
    isHead: false,
    isSymbolic: true,
    worktreePath: '',
  ),
  // Gone branch that will be VISIBLE with filter (matches "done")
  RefInfo(
    fullName: 'refs/heads/feature/done-cleanup',
    shortName: 'feature/done-cleanup',
    kind: RefKind.localBranch,
    target: 'jkl012',
    upstream: 'origin/feature/done-cleanup',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: true,
    isGone: true,
    isHead: false,
    isSymbolic: true,
    worktreePath: '',
  ),
];

final _testRefSnapshot = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'abc123',
  ),
  refs: _testBranches,
  refCountGuardTripped: false,
  totalRefCount: _testBranches.length,
);

void main() {
  group('SidebarPanel', () {
    testWidgets(
      'select-all-gone button only selects branches matching the active filter',
      (tester) async {
        // Arrange: Override the provider to return test branches
        final overrides = <Override>[
          repoRefsProvider(_testIdentity).overrideWithValue(_testRefSnapshot),
          repoSessionProvider(_testIdentity).overrideWith(
            (ref) => RepoSessionController(
              _FakeGbmBindings(),
              _testIdentity,
              _FakeRecentsRepository(),
            ),
          ),
        ];

        await pumpGbmWidget(
          tester,
          child: SidebarPanel(identity: _testIdentity, filterFocusNode: null),
          overrides: overrides,
          wrapInScaffold: true,
        );

        // Verify initial state: no filter, button should be enabled
        expect(
          find.byTooltip('Select all branches with a gone upstream'),
          findsOneWidget,
        );

        // Step 1: Enter a filter that hides feature/old-feature but shows
        // feature/done-cleanup
        await tester.enterText(find.byType(TextField), 'done');
        await tester.pumpAndSettle();

        // At this point, only feature/done-cleanup (a gone branch) should be
        // visible. feature/old-feature should be hidden.

        // Step 2: Click the select-all-gone button
        await tester.tap(
          find.byTooltip('Select all branches with a gone upstream'),
        );
        await tester.pumpAndSettle();

        // Step 3: Verify that only the VISIBLE gone branch is selected,
        // not the hidden one.
        // We check this by looking at the selection state text that appears.
        expect(
          find.text('1 selected'),
          findsOneWidget,
          reason: 'Only the visible gone branch should be selected',
        );

        // The hidden gone branch (feature/old-feature) should NOT be selected
        // even though it matches _isGoneAndBulkSelectable. This is the bug fix:
        // the button should respect the active filter.
      },
    );

    testWidgets(
      'select-all-gone button is disabled when no gone branches match the filter',
      (tester) async {
        final overrides = <Override>[
          repoRefsProvider(_testIdentity).overrideWithValue(_testRefSnapshot),
          repoSessionProvider(_testIdentity).overrideWith(
            (ref) => RepoSessionController(
              _FakeGbmBindings(),
              _testIdentity,
              _FakeRecentsRepository(),
            ),
          ),
        ];

        await pumpGbmWidget(
          tester,
          child: SidebarPanel(identity: _testIdentity, filterFocusNode: null),
          overrides: overrides,
          wrapInScaffold: true,
        );

        // Enter a filter that matches only non-gone branches (auth is active,
        // not gone)
        await tester.enterText(find.byType(TextField), 'auth');
        await tester.pumpAndSettle();

        // The button should now be disabled because there are no gone branches
        // matching the filter
        final iconButton = find.descendant(
          of: find.byTooltip('Select all branches with a gone upstream'),
          matching: find.byType(IconButton),
        );
        expect(iconButton, findsOneWidget);

        // Check that the button is disabled by verifying it has no onPressed
        final widget = tester.widget<IconButton>(iconButton);
        expect(
          widget.onPressed,
          isNull,
          reason:
              'Button should be disabled when no gone branches match filter',
        );
      },
    );
  });
}
