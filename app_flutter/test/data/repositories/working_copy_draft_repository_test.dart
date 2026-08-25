import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/working_copy_draft_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const RepoIdentity _repo1 = RepoIdentity(
  workDir: '/repo1',
  gitDir: '/repo1/.git',
);
const RepoIdentity _repo2 = RepoIdentity(
  workDir: '/repo2',
  gitDir: '/repo2/.git',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  /// A container wired to the same [SharedPreferences] instance as the last
  /// one, so a test can throw the container away and build a new one -- which
  /// is what a restart looks like from the draft's point of view.
  ProviderContainer container() {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('WorkingCopyDraft', () {
    test('has correct default values', () {
      const draft = WorkingCopyDraft();
      expect(draft.summary, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 0.0);
    });

    test('copyWith creates new instance with updated summary', () {
      const draft = WorkingCopyDraft(
        summary: 'initial',
        description: 'desc',
        diffScrollOffset: 10.0,
      );
      final updated = draft.copyWith(summary: 'updated');

      expect(updated.summary, 'updated');
      expect(updated.description, 'desc');
      expect(updated.diffScrollOffset, 10.0);
    });

    test('copyWith creates new instance with updated description', () {
      const draft = WorkingCopyDraft(
        summary: 'summary',
        description: 'initial',
        diffScrollOffset: 10.0,
      );
      final updated = draft.copyWith(description: 'updated');

      expect(updated.summary, 'summary');
      expect(updated.description, 'updated');
      expect(updated.diffScrollOffset, 10.0);
    });

    test('copyWith creates new instance with updated diffScrollOffset', () {
      const draft = WorkingCopyDraft(
        summary: 'summary',
        description: 'desc',
        diffScrollOffset: 10.0,
      );
      final updated = draft.copyWith(diffScrollOffset: 20.0);

      expect(updated.summary, 'summary');
      expect(updated.description, 'desc');
      expect(updated.diffScrollOffset, 20.0);
    });
  });

  group('workingCopyDraftProvider', () {
    test('starts with default WorkingCopyDraft', () {
      final ProviderContainer c = container();

      final draft = c.read(workingCopyDraftProvider(_repo1));

      expect(draft.summary, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 0.0);
    });

    test('updateSummary updates summary only', () {
      final ProviderContainer c = container();

      c
          .read(workingCopyDraftProvider(_repo1).notifier)
          .updateSummary('new summary');

      final draft = c.read(workingCopyDraftProvider(_repo1));
      expect(draft.summary, 'new summary');
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 0.0);
    });

    test('updateDescription updates description only', () {
      final ProviderContainer c = container();

      c
          .read(workingCopyDraftProvider(_repo1).notifier)
          .updateDescription('new description');

      final draft = c.read(workingCopyDraftProvider(_repo1));
      expect(draft.summary, isEmpty);
      expect(draft.description, 'new description');
      expect(draft.diffScrollOffset, 0.0);
    });

    test('updateDiffScrollOffset updates offset only', () {
      final ProviderContainer c = container();

      c
          .read(workingCopyDraftProvider(_repo1).notifier)
          .updateDiffScrollOffset(42.5);

      final draft = c.read(workingCopyDraftProvider(_repo1));
      expect(draft.summary, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 42.5);
    });

    test('multiple updates accumulate correctly', () {
      final ProviderContainer c = container();

      final notifier = c.read(workingCopyDraftProvider(_repo1).notifier);

      notifier.updateSummary('summary text');
      notifier.updateDescription('description text');
      notifier.updateDiffScrollOffset(100.0);

      final draft = c.read(workingCopyDraftProvider(_repo1));
      expect(draft.summary, 'summary text');
      expect(draft.description, 'description text');
      expect(draft.diffScrollOffset, 100.0);
    });

    test('reset clears all fields back to defaults', () {
      final ProviderContainer c = container();

      final notifier = c.read(workingCopyDraftProvider(_repo1).notifier);

      notifier.updateSummary('summary text');
      notifier.updateDescription('description text');
      notifier.updateDiffScrollOffset(100.0);

      notifier.reset();

      final draft = c.read(workingCopyDraftProvider(_repo1));
      expect(draft.summary, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 0.0);
    });

    test('family isolates drafts by RepoIdentity', () {
      final ProviderContainer c = container();

      // Update draft for _repo1
      c
          .read(workingCopyDraftProvider(_repo1).notifier)
          .updateSummary('summary1');

      // Update draft for _repo2
      c
          .read(workingCopyDraftProvider(_repo2).notifier)
          .updateSummary('summary2');

      // Verify isolation
      final draft1 = c.read(workingCopyDraftProvider(_repo1));
      final draft2 = c.read(workingCopyDraftProvider(_repo2));

      expect(draft1.summary, 'summary1');
      expect(draft2.summary, 'summary2');
    });

    test(
      'different identity instances with same values are treated as same key',
      () {
        final ProviderContainer c = container();

        const RepoIdentity sameAgain = RepoIdentity(
          workDir: '/repo1',
          gitDir: '/repo1/.git',
        );

        // Both identities have the same values and should be equal
        expect(_repo1, sameAgain);

        // Update using _repo1
        c
            .read(workingCopyDraftProvider(_repo1).notifier)
            .updateSummary('shared summary');

        // Read using sameAgain should get the same state
        final draft = c.read(workingCopyDraftProvider(sameAgain));
        expect(draft.summary, 'shared summary');
      },
    );
  });

  group('WorkingCopyDraftRepository -- the draft survives a restart', () {
    /// Drops the container and builds a new one against the same
    /// SharedPreferences. That is what relaunching the app looks like from
    /// the draft's point of view: fresh providers, same disk.
    Future<WorkingCopyDraft> afterRestart(
      ProviderContainer before,
      RepoIdentity identity,
    ) async {
      // The write is coalesced behind an await, so let it land first.
      await Future<void>.delayed(Duration.zero);
      before.dispose();
      return container().read(workingCopyDraftProvider(identity));
    }

    test('a half-written message is still there next launch', () async {
      final ProviderContainer c = container();
      c
          .read(workingCopyDraftProvider(_repo1).notifier)
          .updateSummary('fix: half a thought');
      c
          .read(workingCopyDraftProvider(_repo1).notifier)
          .updateDescription('and the body');

      final WorkingCopyDraft draft = await afterRestart(c, _repo1);

      expect(draft.summary, 'fix: half a thought');
      expect(draft.description, 'and the body');
    });

    test('two repositories keep two drafts', () async {
      final ProviderContainer c = container();
      c.read(workingCopyDraftProvider(_repo1).notifier).updateSummary('one');
      c.read(workingCopyDraftProvider(_repo2).notifier).updateSummary('two');

      await Future<void>.delayed(Duration.zero);
      c.dispose();
      final ProviderContainer restarted = container();

      expect(restarted.read(workingCopyDraftProvider(_repo1)).summary, 'one');
      expect(restarted.read(workingCopyDraftProvider(_repo2)).summary, 'two');
    });

    test('the scroll offset is not persisted', () async {
      // Nothing is selected after a restart, so restoring an offset into
      // some other file's diff would scroll an unrelated thing.
      final ProviderContainer c = container();
      c.read(workingCopyDraftProvider(_repo1).notifier).updateSummary('x');
      c
          .read(workingCopyDraftProvider(_repo1).notifier)
          .updateDiffScrollOffset(400);

      final WorkingCopyDraft draft = await afterRestart(c, _repo1);

      expect(draft.summary, 'x');
      expect(draft.diffScrollOffset, 0.0);
    });

    test('a committed message does not come back', () async {
      // reset() has to reach the disk, not just the field: the message has
      // become a commit, and offering it again invites committing it twice.
      final ProviderContainer c = container();
      c.read(workingCopyDraftProvider(_repo1).notifier).updateSummary('done');
      await Future<void>.delayed(Duration.zero);
      c.read(workingCopyDraftProvider(_repo1).notifier).reset();

      final WorkingCopyDraft draft = await afterRestart(c, _repo1);

      expect(draft.summary, isEmpty);
      expect(draft.description, isEmpty);
    });

    test('a stored value of the wrong shape reads as an empty draft', () {
      // Never a crash and never a half-message: a body without its subject
      // is worse than starting over.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'workingCopyDraft:/repo1': <String>['only one entry'],
      });
      return SharedPreferences.getInstance().then((SharedPreferences p) {
        expect(WorkingCopyDraftRepository(p).read(_repo1).summary, isEmpty);
      });
    });

    test('rapid edits coalesce but the last one still lands', () async {
      // The write is fire-and-forget behind an in-flight guard; the point of
      // the guard is to skip the middle keystrokes, never the final one.
      final ProviderContainer c = container();
      final WorkingCopyDraftController notifier = c.read(
        workingCopyDraftProvider(_repo1).notifier,
      );
      for (int i = 0; i < 20; i++) {
        notifier.updateSummary('keystroke $i');
      }

      final WorkingCopyDraft draft = await afterRestart(c, _repo1);

      expect(draft.summary, 'keystroke 19');
    });
  });
}
