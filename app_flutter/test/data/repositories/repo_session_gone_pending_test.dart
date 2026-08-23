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
