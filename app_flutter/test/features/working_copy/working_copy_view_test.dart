import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart'
    show RepoSessionController, RepoSessionState, repoSessionProvider;
import 'package:gbm_flutter/data/repositories/working_copy_draft_repository.dart'
    show workingCopyDraftProvider;
import 'package:gbm_flutter/data/repositories/working_copy_repository.dart'
    as wc;
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';

import '../../support/pump_app.dart';

void main() {
  group('WorkingCopyView', () {
    final identity = RepoIdentity(
      workDir: '/test/repo',
      gitDir: '/test/repo/.git',
    );

    final unstagedEntry = const WorkingCopyEntry(
      path: 'lib/main.dart',
      oldPath: '',
      untracked: false,
      staged: false,
      indexStatus: FileChangeKind.modified,
      hasUnstagedChange: true,
      worktreeStatus: FileChangeKind.modified,
      conflict: ConflictKind.none,
      ancestorBlob: '',
      oursBlob: '',
      theirsBlob: '',
      similarity: 0,
      isSubmodule: false,
      isConflicted: false,
    );

    final stagedEntry = const WorkingCopyEntry(
      path: 'pubspec.yaml',
      oldPath: '',
      untracked: false,
      staged: true,
      indexStatus: FileChangeKind.modified,
      hasUnstagedChange: false,
      worktreeStatus: FileChangeKind.modified,
      conflict: ConflictKind.none,
      ancestorBlob: '',
      oursBlob: '',
      theirsBlob: '',
      similarity: 0,
      isSubmodule: false,
      isConflicted: false,
    );

    testWidgets('renders two-column board with staged and unstaged files', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                _FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(
                WorkingCopyStatus(entries: [stagedEntry, unstagedEntry]),
              ),
          wc.repoLastDiffProvider(identity).overrideWithValue(null),
        ],
      );

      // Check that board renders
      expect(find.text('UNSTAGED'), findsOneWidget);
      expect(find.text('STAGED'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);
    });

    testWidgets(
      'renders the conflicted section without a layout exception',
      (tester) async {
        final conflictedEntry = const WorkingCopyEntry(
          path: 'lib/conflicted.dart',
          oldPath: '',
          untracked: false,
          staged: false,
          indexStatus: FileChangeKind.modified,
          hasUnstagedChange: false,
          worktreeStatus: FileChangeKind.modified,
          conflict: ConflictKind.bothModified,
          ancestorBlob: '',
          oursBlob: '',
          theirsBlob: '',
          similarity: 0,
          isSubmodule: false,
          isConflicted: true,
        );

        await pumpGbmWidget(
          tester,
          child: SizedBox(
            width: 800,
            height: 600,
            child: WorkingCopyView(identity: identity),
          ),
          overrides: [
            repoSessionProvider(identity).overrideWith(
              (ref) => _FakeRepoSessionController(
                identity,
                const RepoSessionState(),
              ),
            ),
            wc
                .repoWorkingCopyStatusProvider(identity)
                .overrideWithValue(
                  WorkingCopyStatus(entries: [conflictedEntry]),
                ),
            wc.repoLastDiffProvider(identity).overrideWithValue(null),
          ],
        );

        // The conflicted-section Column (header + Expanded(ListView)) sits
        // in a MainAxisSize.min Column with no bounded-height wrapper --
        // without one, RenderFlex gets unbounded height constraints from
        // its unconstrained-height ancestor and the framework throws
        // during layout/paint instead of the file list actually rendering.
        expect(tester.takeException(), isNull);
        expect(find.text('CONFLICTED'), findsOneWidget);
        expect(find.text('lib/conflicted.dart'), findsOneWidget);
      },
    );

    testWidgets('commit message box is visible', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                _FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(WorkingCopyStatus(entries: [stagedEntry])),
          wc.repoLastDiffProvider(identity).overrideWithValue(null),
        ],
      );

      // Check for commit box elements
      expect(find.text('Commit summary'), findsOneWidget);
      expect(find.text('Commit'), findsOneWidget);
      expect(find.text('Amend'), findsOneWidget);
    });

    testWidgets('shows empty state when no changes', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                _FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(WorkingCopyStatus(entries: [])),
          wc.repoLastDiffProvider(identity).overrideWithValue(null),
        ],
      );

      expect(find.text('No changes'), findsOneWidget);
    });

    testWidgets('untracked files are included in unstaged column', (
      tester,
    ) async {
      final untrackedEntry = const WorkingCopyEntry(
        path: 'new_file.dart',
        oldPath: '',
        untracked: true,
        staged: false,
        indexStatus: FileChangeKind.added,
        hasUnstagedChange: false,
        worktreeStatus: FileChangeKind.added,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      );

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                _FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(
                WorkingCopyStatus(entries: [unstagedEntry, untrackedEntry]),
              ),
          wc.repoLastDiffProvider(identity).overrideWithValue(null),
        ],
      );

      // Both should appear in unstaged
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('new_file.dart'), findsOneWidget);
    });

    testWidgets('commit draft survives a widget rebuild (e.g. switching to the '
        'History tab and back via ShellRoute)', (tester) async {
      final ProviderContainer container = await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                _FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(WorkingCopyStatus(entries: [stagedEntry])),
          wc.repoLastDiffProvider(identity).overrideWithValue(null),
        ],
      );

      await tester.enterText(find.byType(TextField).at(0), 'my summary');
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'my description');
      await tester.pump();

      final draftBefore = container.read(workingCopyDraftProvider(identity));
      expect(draftBefore.summary, 'my summary');
      expect(draftBefore.description, 'my description');

      // Simulate the ShellRoute disposing WorkingCopyView (e.g. switching
      // to the History tab) by pumping an unrelated widget into the SAME
      // provider container: this tears down WorkingCopyView's local State
      // -- including its TextEditingControllers -- but the container, and
      // therefore workingCopyDraftProvider's state, survives, exactly like
      // the app's single top-level ProviderScope does across navigation.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );

      // Simulate switching back to Working Copy: a brand new
      // WorkingCopyView widget/State is created and must re-seed its
      // controllers from the surviving draft rather than starting blank.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorkingCopyView(identity: identity),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('my summary'), findsOneWidget);
      expect(find.text('my description'), findsOneWidget);
    });
  });
}

/// Fake controller for testing that just holds a static state.
///
/// [RepoSessionController]'s constructor unconditionally opens a real FFI
/// session, so it needs a fake [GbmBindings] whose `sessionOpen` returns
/// `nullptr`: `RepoSessionController._open()` treats a null session as
/// "open failed" and returns immediately, before touching anything else on
/// `_bindings` or `_recents` (same pattern as `sidebar_panel_test.dart`'s
/// `_FakeGbmBindings`/`_FakeRecentsRepository`).
class _FakeRepoSessionController extends RepoSessionController {
  _FakeRepoSessionController(RepoIdentity identity, RepoSessionState initialState)
    : super(_FakeGbmBindings(), identity, _FakeRecentsRepository()) {
    state = initialState;
  }

  /// Dummy methods called by the view but not tested here.
  @override
  void resolveConflict(
    String path,
    dynamic resolution, {
    bool oursBlobMissing = false,
    bool theirsBlobMissing = false,
    String? resolvedContent,
  }) {}

  @override
  void restorePaths(List<String> paths, {String source = '', bool staged = false}) {}

  @override
  void requestWorkingTreeContent(String path) {}
}

class _FakeGbmBindings implements GbmBindings {
  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          nullptr;

  @override
  LastResultJsonLenDart get lastResultJsonLen => () => 0;

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not implemented for testing');
}

class _FakeRecentsRepository implements RecentsRepository {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not implemented for testing');
}
