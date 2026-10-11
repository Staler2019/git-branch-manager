import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/prepared_message_policy.dart';
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

  group('amend is a mode', () {
    test('entering snapshots what the box held', () {
      final ProviderContainer c = container();
      final WorkingCopyDraftController notifier = c.read(
        workingCopyDraftProvider(_repo1).notifier,
      );
      notifier.updateSummary('a new thought');
      notifier.updateDescription('with a body');

      notifier.beginAmend();

      final WorkingCopyDraft draft = c.read(workingCopyDraftProvider(_repo1));
      expect(draft.amending, isTrue);
      expect(draft.preAmendSummary, 'a new thought');
      expect(draft.preAmendDescription, 'with a body');
    });

    test('entering does not itself fill in a message', () {
      // HEAD's message arrives asynchronously. Filling anything in here
      // would mean guessing.
      final ProviderContainer c = container();
      final WorkingCopyDraftController notifier = c.read(
        workingCopyDraftProvider(_repo1).notifier,
      );
      notifier.updateSummary('mine');

      notifier.beginAmend();

      expect(c.read(workingCopyDraftProvider(_repo1)).summary, 'mine');
    });

    test('the message arriving replaces the box contents', () {
      final ProviderContainer c = container();
      final WorkingCopyDraftController notifier = c.read(
        workingCopyDraftProvider(_repo1).notifier,
      );
      notifier.updateSummary('mine');
      notifier.beginAmend();

      notifier.applyAmendedMessage(
        summary: 'HEAD subject',
        description: 'body',
      );

      final WorkingCopyDraft draft = c.read(workingCopyDraftProvider(_repo1));
      expect(draft.summary, 'HEAD subject');
      expect(draft.description, 'body');
      expect(
        draft.preAmendSummary,
        'mine',
        reason:
            'the snapshot is what cancelling restores, so filling the box '
            'must not touch it',
      );
    });

    test('a message arriving outside the mode is ignored', () {
      // The reply can land after the user has already cancelled; applying it
      // then would overwrite the message they went back to.
      final ProviderContainer c = container();
      final WorkingCopyDraftController notifier = c.read(
        workingCopyDraftProvider(_repo1).notifier,
      );
      notifier.updateSummary('mine');

      notifier.applyAmendedMessage(summary: 'HEAD subject', description: '');

      expect(c.read(workingCopyDraftProvider(_repo1)).summary, 'mine');
    });

    test('cancelling puts back exactly what was there', () {
      final ProviderContainer c = container();
      final WorkingCopyDraftController notifier = c.read(
        workingCopyDraftProvider(_repo1).notifier,
      );
      notifier.updateSummary('mine');
      notifier.updateDescription('my body');
      notifier.beginAmend();
      notifier.applyAmendedMessage(summary: 'HEAD subject', description: 'hb');

      notifier.cancelAmend();

      final WorkingCopyDraft draft = c.read(workingCopyDraftProvider(_repo1));
      expect(draft.amending, isFalse);
      expect(draft.summary, 'mine');
      expect(draft.description, 'my body');
      expect(draft.preAmendSummary, isEmpty);
    });

    test(
      'entering twice does not overwrite the snapshot with HEADs message',
      () {
        // A second beginAmend() after the box has been filled in would snapshot
        // the commit's own message as "what the user was writing".
        final ProviderContainer c = container();
        final WorkingCopyDraftController notifier = c.read(
          workingCopyDraftProvider(_repo1).notifier,
        );
        notifier.updateSummary('mine');
        notifier.beginAmend();
        notifier.applyAmendedMessage(summary: 'HEAD subject', description: '');

        notifier.beginAmend();
        notifier.cancelAmend();

        expect(c.read(workingCopyDraftProvider(_repo1)).summary, 'mine');
      },
    );

    test('the mode is not persisted across a restart', () async {
      // Coming back to a box silently poised to rewrite a commit nobody
      // remembers is the one thing this must not do.
      final ProviderContainer c = container();
      final WorkingCopyDraftController notifier = c.read(
        workingCopyDraftProvider(_repo1).notifier,
      );
      notifier.beginAmend();
      notifier.applyAmendedMessage(summary: 'HEAD subject', description: '');
      await Future<void>.delayed(Duration.zero);
      c.dispose();

      final WorkingCopyDraft draft = container().read(
        workingCopyDraftProvider(_repo1),
      );
      expect(draft.summary, 'HEAD subject');
      expect(draft.amending, isFalse);
    });
  });

  // Rulings ①③⑨⑪: the controller holds the episode, so leaving the Working
  // Copy tab and coming back neither fills the box twice nor forgets what it
  // held before the merge.
  group('a prepared message episode', () {
    late ProviderContainer c;
    late WorkingCopyDraftController notifier;
    WorkingCopyDraft draft() => c.read(workingCopyDraftProvider(_repo1));

    PreparedMessageAction reconcile({
      bool pending = true,
      PreparedReplyStatus reply = PreparedReplyStatus.none,
      bool overwrite = true,
      int refsEpoch = 0,
    }) => notifier.reconcilePreparedMessage(
      pending: pending,
      reply: reply,
      summary: "Merge branch 'topic'",
      description: 'merged body',
      raw: "Merge branch 'topic'\n\nmerged body",
      head: 'deadbeef',
      overwrite: overwrite,
      refsEpoch: refsEpoch,
    );

    /// The merge ended without an in-app commit, and fresh refs show HEAD
    /// where the episode left it: an Abort (Slice D R2).
    PreparedMessageAction endAtSameHead() {
      expect(reconcile(pending: false), PreparedMessageAction.checkHead);
      return reconcile(pending: false, refsEpoch: 1);
    }

    setUp(() {
      c = container();
      notifier = c.read(workingCopyDraftProvider(_repo1).notifier);
      notifier.updateSummary('mine');
      notifier.updateDescription('my body');
    });

    test('starting asks for the message and leaves the box alone', () {
      expect(reconcile(), PreparedMessageAction.startAndRequest);
      expect(draft().preparedEpisodeActive, isTrue);
      expect(draft().summary, 'mine');
    });

    test('the reply replaces the box', () {
      reconcile();

      expect(
        reconcile(reply: PreparedReplyStatus.message),
        PreparedMessageAction.replace,
      );
      expect(draft().summary, "Merge branch 'topic'");
      expect(draft().description, 'merged body');
    });

    test('a second pass after filling changes nothing', () {
      reconcile();
      reconcile(reply: PreparedReplyStatus.message);
      notifier.updateSummary('edited during the merge');

      expect(
        reconcile(reply: PreparedReplyStatus.message),
        PreparedMessageAction.nothing,
      );
      expect(draft().summary, 'edited during the merge');
    });

    test('an abort with the autofill untouched puts back the old text', () {
      reconcile();
      reconcile(reply: PreparedReplyStatus.message);

      expect(endAtSameHead(), PreparedMessageAction.restoreAndEnd);
      expect(draft().summary, 'mine');
      expect(draft().description, 'my body');
      expect(draft().preparedEpisodeActive, isFalse);
    });

    test('an abort after the user edited keeps their edit', () {
      reconcile();
      reconcile(reply: PreparedReplyStatus.message);
      notifier.updateDescription('my own words');

      expect(endAtSameHead(), PreparedMessageAction.end);
      expect(draft().summary, "Merge branch 'topic'");
      expect(draft().description, 'my own words');
      expect(draft().preparedEpisodeActive, isFalse);
    });

    test('a kept box is never restored, since nothing was autofilled', () {
      reconcile();
      expect(
        reconcile(reply: PreparedReplyStatus.message, overwrite: false),
        PreparedMessageAction.keep,
      );

      expect(endAtSameHead(), PreparedMessageAction.end);
      expect(draft().summary, 'mine');
    });

    test('editing only the summary counts as the user\'s edit', () {
      reconcile();
      reconcile(reply: PreparedReplyStatus.message);
      notifier.updateSummary('my subject');

      expect(endAtSameHead(), PreparedMessageAction.end);
      expect(draft().summary, 'my subject');
    });

    // The decision is made once per episode: a box the user empties after
    // a kept reply is not filled behind their back.
    test('a kept box stays kept after the user empties it', () {
      reconcile();
      reconcile(reply: PreparedReplyStatus.message, overwrite: false);
      notifier.updateSummary('');
      notifier.updateDescription('');

      expect(
        reconcile(reply: PreparedReplyStatus.message, overwrite: false),
        PreparedMessageAction.nothing,
      );
      expect(draft().summary, isEmpty);
    });

    test('an empty box that was never filled is not "restored"', () {
      notifier.updateSummary('');
      notifier.updateDescription('');
      reconcile();
      reconcile(reply: PreparedReplyStatus.failed);

      expect(endAtSameHead(), PreparedMessageAction.end);
    });

    test('a merge starting in amend mode puts the pre-amend text back', () {
      notifier.beginAmend();
      notifier.applyAmendedMessage(summary: 'HEAD subject', description: 'hb');

      expect(reconcile(), PreparedMessageAction.cancelAmendAndStart);
      expect(draft().amending, isFalse);
      expect(draft().summary, 'mine');
      expect(draft().description, 'my body');
      expect(draft().preparedEpisodeActive, isTrue);

      reconcile(reply: PreparedReplyStatus.message);
      expect(endAtSameHead(), PreparedMessageAction.restoreAndEnd);
      expect(draft().summary, 'mine');
    });

    test('a merge ending under an outstanding commit restores nothing', () {
      reconcile();
      reconcile(reply: PreparedReplyStatus.message);
      notifier.commitSubmitted(0, head: 'deadbeef', headKnown: true);

      expect(reconcile(pending: false), PreparedMessageAction.end);
      expect(draft().summary, "Merge branch 'topic'");

      notifier.commitLanded();
      expect(draft().summary, isEmpty);
      expect(draft().pendingCommitSeq, isNull);
    });

    // Slice D R2 (使用者 2026-10-11 「分辨 commit，其他照 Abort」).
    group('ending without an in-app commit', () {
      PreparedMessageAction ended({
        String head = 'deadbeef',
        int refsEpoch = 1,
        int replySeq = 0,
        List<String>? parents,
        bool error = false,
      }) => notifier.reconcilePreparedMessage(
        pending: false,
        reply: PreparedReplyStatus.message,
        summary: "Merge branch 'topic'",
        description: 'merged body',
        raw: "Merge branch 'topic'\n\nmerged body",
        head: head,
        overwrite: true,
        refsEpoch: refsEpoch,
        commitMetaReplySeq: replySeq,
        parentsOf: (String oid) => oid == head ? parents : null,
        lastErrorPresent: error,
      );

      /// Filled over 'mine' / 'my body'; the merge has just stopped pending
      /// and fresh refs show HEAD at [head].
      void filledThenMovedTo(String head) {
        reconcile();
        reconcile(reply: PreparedReplyStatus.message);
        expect(ended(refsEpoch: 0), PreparedMessageAction.checkHead);
        expect(ended(head: head), PreparedMessageAction.checkParent);
      }

      test('a commit of this merge clears the box', () {
        filledThenMovedTo('cafebabe');
        expect(
          ended(head: 'cafebabe', parents: <String>['deadbeef', 'f00d']),
          PreparedMessageAction.clearAndEnd,
        );
        expect(draft().summary, isEmpty);
        expect(draft().preparedEpisodeActive, isFalse);
      });

      test('a reset elsewhere puts back the untouched autofill', () {
        filledThenMovedTo('0ddba11');
        expect(
          ended(head: '0ddba11', parents: <String>['beefcafe']),
          PreparedMessageAction.restoreAndEnd,
        );
        expect(draft().summary, 'mine');
      });

      test('a reset elsewhere keeps an edited message', () {
        reconcile();
        reconcile(reply: PreparedReplyStatus.message);
        notifier.updateDescription('my own words');
        ended(refsEpoch: 0);
        ended(head: '0ddba11');
        expect(
          ended(head: '0ddba11', parents: <String>['beefcafe']),
          PreparedMessageAction.end,
        );
        expect(draft().description, 'my own words');
      });

      test('a reset to a root commit is not a commit, and does not throw', () {
        filledThenMovedTo('0ddba11');
        expect(
          ended(head: '0ddba11', parents: const <String>[]),
          PreparedMessageAction.restoreAndEnd,
        );
      });

      test('a reply without the commit counts as no answer', () {
        filledThenMovedTo('cafebabe');
        expect(ended(head: 'cafebabe'), PreparedMessageAction.nothing);
        expect(
          ended(head: 'cafebabe', replySeq: 1),
          PreparedMessageAction.restoreAndEnd,
        );
      });

      test('an error while waiting falls back to the Abort rule', () {
        reconcile();
        reconcile(reply: PreparedReplyStatus.message);
        ended(refsEpoch: 0);
        expect(
          ended(refsEpoch: 0, error: true),
          PreparedMessageAction.restoreAndEnd,
        );
        expect(draft().summary, 'mine');
      });

      test('a merge pending again ends the wait instead of the episode', () {
        reconcile();
        reconcile(reply: PreparedReplyStatus.message);
        ended(refsEpoch: 0);
        expect(draft().headCheckEpoch, 0);

        expect(reconcile(), PreparedMessageAction.nothing);
        expect(draft().headCheckEpoch, isNull);
        expect(draft().preparedEpisodeActive, isTrue);
        expect(draft().summary, "Merge branch 'topic'");
      });

      // plan-verifier epoch 1: an unfilled episode records no HEAD, and
      // "HEAD differs from ''" would wipe the user's text.
      test('an unfilled episode keeps the text with no HEAD check', () {
        reconcile();
        expect(
          ended(head: 'cafebabe', refsEpoch: 0),
          PreparedMessageAction.end,
        );
        expect(draft().summary, 'mine');
      });

      test(
        'an unfilled episode started over amend keeps the pre-amend text',
        () {
          notifier.beginAmend();
          notifier.applyAmendedMessage(
            summary: 'HEAD subject',
            description: 'hb',
          );
          expect(reconcile(), PreparedMessageAction.cancelAmendAndStart);
          expect(
            ended(head: 'cafebabe', refsEpoch: 0),
            PreparedMessageAction.end,
          );
          expect(draft().summary, 'mine');
          expect(draft().description, 'my body');
        },
      );
    });

    test('a new episode after the last one ended starts again', () {
      reconcile();
      reconcile(reply: PreparedReplyStatus.message);
      endAtSameHead();

      expect(reconcile(), PreparedMessageAction.startAndRequest);
      expect(draft().preparedFilled, isFalse);
    });
  });
}
