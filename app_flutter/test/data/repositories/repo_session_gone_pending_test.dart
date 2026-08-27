import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/remote_prune_preview_entry.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

GbmEvent _prunePreviewEvent(String remote, List<String> shortRefs) {
  return GbmEvent(
    GbmEventType.remotePrunePreviewReady,
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'remote': remote,
        'refs': <Map<String, dynamic>>[
          for (final String ref in shortRefs) <String, dynamic>{'ref': ref},
        ],
      }),
    ),
  );
}

void main() {
  group('RemotePrunePreviewEntry.fullRefName', () {
    test('expands the short name git prints into a full ref name', () {
      // RemoteOps.h:23-25 documents `ref` as the *short* name -- what
      // `git branch -d -r` accepts -- while RefInfo.upstream and a remote
      // branch's fullName are both `refs/remotes/...`. Comparing the two
      // forms directly would never match and the gone marking would
      // silently never appear.
      expect(
        const RemotePrunePreviewEntry(ref: 'origin/feature/old').fullRefName,
        'refs/remotes/origin/feature/old',
      );
    });

    test('leaves an already-full name alone', () {
      // Defensive: if the C++ side ever starts emitting full names, this
      // must not produce refs/remotes/refs/remotes/...
      expect(
        const RemotePrunePreviewEntry(
          ref: 'refs/remotes/origin/feature/old',
        ).fullRefName,
        'refs/remotes/origin/feature/old',
      );
    });

    test('keeps slashes in a nested branch name', () {
      expect(
        const RemotePrunePreviewEntry(ref: 'upstream/a/b/c').fullRefName,
        'refs/remotes/upstream/a/b/c',
      );
    });
  });

  group('RepoSessionState gone-pending set', () {
    test('defaults to empty', () {
      const RepoSessionState state = RepoSessionState();
      expect(state.gonePendingByRemote, isEmpty);
      expect(state.gonePendingRefs, isEmpty);
    });

    test('flattens every remote into one set', () {
      final RepoSessionState state = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
            RemotePrunePreviewEntry(ref: 'origin/b'),
          ])
          .withGonePendingFor('upstream', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'upstream/c'),
          ]);

      expect(state.gonePendingRefs, <String>{
        'refs/remotes/origin/a',
        'refs/remotes/origin/b',
        'refs/remotes/upstream/c',
      });
    });

    test('replaces one remote without touching the others', () {
      // `git fetch --all` fires one preview per remote and the replies come
      // back independently. Overwriting the whole map would let whichever
      // reply arrived first be erased by the second.
      final RepoSessionState first = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
          ])
          .withGonePendingFor('upstream', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'upstream/c'),
          ]);

      final RepoSessionState second = first.withGonePendingFor(
        'origin',
        const <RemotePrunePreviewEntry>[
          RemotePrunePreviewEntry(ref: 'origin/z'),
        ],
      );

      expect(second.gonePendingRefs, <String>{
        'refs/remotes/origin/z',
        'refs/remotes/upstream/c',
      });
    });

    test('an empty reply drops that remote entirely', () {
      // A remote with nothing to prune must stop contributing, or a ref
      // pruned in a terminal would stay marked forever.
      final RepoSessionState state = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
          ])
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[]);

      expect(state.gonePendingByRemote, isEmpty);
      expect(state.gonePendingRefs, isEmpty);
    });

    test('does not mutate the state it was called on', () {
      final RepoSessionState first = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
          ]);
      first.withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
        RemotePrunePreviewEntry(ref: 'origin/b'),
      ]);

      expect(first.gonePendingRefs, <String>{'refs/remotes/origin/a'});
    });
  });

  group('RepoSessionState.withGonePendingRemoved', () {
    test('drops exactly the refs that were pruned', () {
      final RepoSessionState state = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
            RemotePrunePreviewEntry(ref: 'origin/b'),
          ])
          .withGonePendingRemoved('origin', const <String>[
            'refs/remotes/origin/a',
          ]);

      expect(state.gonePendingRefs, <String>{'refs/remotes/origin/b'});
    });

    test('accepts the short form the Prune dialog sends', () {
      // The two call sites disagreed on form for as long as both existed:
      // prune_remote_branches_dialog.dart passes `preview.refs.map((e) =>
      // e.ref)` -- short names -- while the sidebar's own prune actions
      // passed full `refs/remotes/...` names. Those two actions are deleted
      // now (選單不再出現 prune), and the post-fetch automatic prune sends
      // full names in their place, so the disagreement outlived them. The
      // map stores full names, so an un-normalised removal would silently
      // no-op for every dialog-initiated prune, which is the common path.
      final RepoSessionState state = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
            RemotePrunePreviewEntry(ref: 'origin/b'),
          ])
          .withGonePendingRemoved('origin', const <String>['origin/a']);

      expect(state.gonePendingRefs, <String>{'refs/remotes/origin/b'});
    });

    test('drops the remote entirely once nothing is left', () {
      // Same reasoning as withGonePendingFor's empty reply: an empty list
      // left behind would later read as "this remote has been checked".
      final RepoSessionState state = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
          ])
          .withGonePendingRemoved('origin', const <String>['origin/a']);

      expect(state.gonePendingByRemote, isEmpty);
    });

    test('leaves other remotes alone', () {
      final RepoSessionState state = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
          ])
          .withGonePendingFor('upstream', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'upstream/c'),
          ])
          .withGonePendingRemoved('origin', const <String>['origin/a']);

      expect(state.gonePendingRefs, <String>{'refs/remotes/upstream/c'});
    });

    test('a remote with nothing recorded is a no-op, not a crash', () {
      final RepoSessionState state = const RepoSessionState()
          .withGonePendingRemoved('origin', const <String>['origin/a']);

      expect(state.gonePendingByRemote, isEmpty);
    });

    test('does not mutate the state it was called on', () {
      final RepoSessionState first = const RepoSessionState()
          .withGonePendingFor('origin', const <RemotePrunePreviewEntry>[
            RemotePrunePreviewEntry(ref: 'origin/a'),
          ]);
      first.withGonePendingRemoved('origin', const <String>['origin/a']);

      expect(first.gonePendingRefs, <String>{'refs/remotes/origin/a'});
    });
  });

  group('a successful prune clears its own gone-pending marks', () {
    test('the pruned refs leave the set, the rest stay', () {
      final FakeRepoSessionController controller = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      addTearDown(controller.dispose);

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>[
          'origin/gone-a',
          'origin/gone-b',
        ]),
      );
      controller.debugRecordPruneRemote(
        remoteName: 'origin',
        refs: <String>['origin/gone-a'],
      );

      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': true,
        'kind': 'prune-remote',
      });

      // Asserted on the state, not on what the sidebar renders: once a ref
      // is really pruned it also vanishes from the refs snapshot, so a
      // rendering assertion goes green even with the removal deleted.
      expect(controller.state.gonePendingRefs, <String>{
        'refs/remotes/origin/gone-b',
      });
    });

    test('a failed prune leaves the marks in place', () {
      // The ref is still there, so it is still gone-pending. Clearing on
      // failure would hide a row the user still has to act on.
      final FakeRepoSessionController controller = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      addTearDown(controller.dispose);

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/gone-a']),
      );
      controller.debugRecordPruneRemote(
        remoteName: 'origin',
        refs: <String>['origin/gone-a'],
      );

      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': false,
        'kind': 'prune-remote',
        'summary': 'nope',
      });

      expect(controller.state.gonePendingRefs, <String>{
        'refs/remotes/origin/gone-a',
      });
    });

    test('a failed prune still pops its queue entry', () {
      // The queue tracks submissions, not successes. Skipping the pop would
      // let this failed request answer for the *next* prune's outcome and
      // clear marks that prune never touched.
      final FakeRepoSessionController controller = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      addTearDown(controller.dispose);

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>[
          'origin/gone-a',
          'origin/gone-b',
        ]),
      );
      controller.debugRecordPruneRemote(
        remoteName: 'origin',
        refs: <String>['origin/gone-a'],
      );
      controller.debugRecordPruneRemote(
        remoteName: 'origin',
        refs: <String>['origin/gone-b'],
      );

      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': false,
        'kind': 'prune-remote',
        'summary': 'nope',
      });
      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': true,
        'kind': 'prune-remote',
      });

      // The second (successful) outcome must answer for gone-b, not gone-a.
      expect(controller.state.gonePendingRefs, <String>{
        'refs/remotes/origin/gone-a',
      });
    });

    test('an outcome with no matching request changes nothing', () {
      final FakeRepoSessionController controller = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      addTearDown(controller.dispose);

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/gone-a']),
      );

      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': true,
        'kind': 'prune-remote',
      });

      expect(controller.state.gonePendingRefs, <String>{
        'refs/remotes/origin/gone-a',
      });
    });
  });

  group('GBM_EVENT_REMOTE_PRUNE_PREVIEW_READY accumulates', () {
    test('a reply lands in both the dialog field and the gone-pending set', () {
      // lastRemotePrunePreview stays last-write-wins for the Prune dialog;
      // gonePendingByRemote is the accumulating, per-remote source the
      // sidebar reads. Both must be written, and neither may replace the
      // other's semantics.
      final FakeRepoSessionController controller = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      addTearDown(controller.dispose);

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>[
          'origin/gone-a',
          'origin/gone-b',
        ]),
      );

      expect(controller.state.lastRemotePrunePreview?.remote, 'origin');
      expect(controller.state.gonePendingRefs, <String>{
        'refs/remotes/origin/gone-a',
        'refs/remotes/origin/gone-b',
      });
    });

    test('two remotes accumulate rather than overwrite', () {
      // `git fetch --all` fires one preview per remote; the replies race.
      final FakeRepoSessionController controller = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      addTearDown(controller.dispose);

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/gone-a']),
      );
      controller.debugHandleEvent(
        _prunePreviewEvent('upstream', <String>['upstream/gone-c']),
      );

      expect(controller.state.gonePendingRefs, <String>{
        'refs/remotes/origin/gone-a',
        'refs/remotes/upstream/gone-c',
      });
    });

    test('an empty reply clears only that remote', () {
      final FakeRepoSessionController controller = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      addTearDown(controller.dispose);

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/gone-a']),
      );
      controller.debugHandleEvent(
        _prunePreviewEvent('upstream', <String>['upstream/gone-c']),
      );
      controller.debugHandleEvent(
        _prunePreviewEvent('origin', const <String>[]),
      );

      expect(controller.state.gonePendingRefs, <String>{
        'refs/remotes/upstream/gone-c',
      });
    });
  });
}
