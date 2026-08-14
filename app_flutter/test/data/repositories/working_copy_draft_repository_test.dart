import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/working_copy_draft_repository.dart';

void main() {
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
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final draft = container.read(
        workingCopyDraftProvider(
          const RepoIdentity(workDir: '/repo1', gitDir: '/repo1/.git'),
        ),
      );

      expect(draft.summary, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 0.0);
    });

    test('updateSummary updates summary only', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final identity = const RepoIdentity(
        workDir: '/repo1',
        gitDir: '/repo1/.git',
      );

      container
          .read(workingCopyDraftProvider(identity).notifier)
          .updateSummary('new summary');

      final draft = container.read(workingCopyDraftProvider(identity));
      expect(draft.summary, 'new summary');
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 0.0);
    });

    test('updateDescription updates description only', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final identity = const RepoIdentity(
        workDir: '/repo1',
        gitDir: '/repo1/.git',
      );

      container
          .read(workingCopyDraftProvider(identity).notifier)
          .updateDescription('new description');

      final draft = container.read(workingCopyDraftProvider(identity));
      expect(draft.summary, isEmpty);
      expect(draft.description, 'new description');
      expect(draft.diffScrollOffset, 0.0);
    });

    test('updateDiffScrollOffset updates offset only', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final identity = const RepoIdentity(
        workDir: '/repo1',
        gitDir: '/repo1/.git',
      );

      container
          .read(workingCopyDraftProvider(identity).notifier)
          .updateDiffScrollOffset(42.5);

      final draft = container.read(workingCopyDraftProvider(identity));
      expect(draft.summary, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 42.5);
    });

    test('multiple updates accumulate correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final identity = const RepoIdentity(
        workDir: '/repo1',
        gitDir: '/repo1/.git',
      );
      final notifier = container.read(
        workingCopyDraftProvider(identity).notifier,
      );

      notifier.updateSummary('summary text');
      notifier.updateDescription('description text');
      notifier.updateDiffScrollOffset(100.0);

      final draft = container.read(workingCopyDraftProvider(identity));
      expect(draft.summary, 'summary text');
      expect(draft.description, 'description text');
      expect(draft.diffScrollOffset, 100.0);
    });

    test('reset clears all fields back to defaults', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final identity = const RepoIdentity(
        workDir: '/repo1',
        gitDir: '/repo1/.git',
      );
      final notifier = container.read(
        workingCopyDraftProvider(identity).notifier,
      );

      notifier.updateSummary('summary text');
      notifier.updateDescription('description text');
      notifier.updateDiffScrollOffset(100.0);

      notifier.reset();

      final draft = container.read(workingCopyDraftProvider(identity));
      expect(draft.summary, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.diffScrollOffset, 0.0);
    });

    test('family isolates drafts by RepoIdentity', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final identity1 = const RepoIdentity(
        workDir: '/repo1',
        gitDir: '/repo1/.git',
      );
      final identity2 = const RepoIdentity(
        workDir: '/repo2',
        gitDir: '/repo2/.git',
      );

      // Update draft for identity1
      container
          .read(workingCopyDraftProvider(identity1).notifier)
          .updateSummary('summary1');

      // Update draft for identity2
      container
          .read(workingCopyDraftProvider(identity2).notifier)
          .updateSummary('summary2');

      // Verify isolation
      final draft1 = container.read(workingCopyDraftProvider(identity1));
      final draft2 = container.read(workingCopyDraftProvider(identity2));

      expect(draft1.summary, 'summary1');
      expect(draft2.summary, 'summary2');
    });

    test(
      'different identity instances with same values are treated as same key',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final identity1 = const RepoIdentity(
          workDir: '/repo1',
          gitDir: '/repo1/.git',
        );
        final identity2 = const RepoIdentity(
          workDir: '/repo1',
          gitDir: '/repo1/.git',
        );

        // Both identities have the same values and should be equal
        expect(identity1, identity2);

        // Update using identity1
        container
            .read(workingCopyDraftProvider(identity1).notifier)
            .updateSummary('shared summary');

        // Read using identity2 should get the same state
        final draft = container.read(workingCopyDraftProvider(identity2));
        expect(draft.summary, 'shared summary');
      },
    );
  });
}
