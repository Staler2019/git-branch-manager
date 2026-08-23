// The three app-level events reachable through RepoSessionController's test
// seams. The fourth -- 「開啟 repo」 -- is emitted on a path
// FakeRepoSessionController cannot execute (its FakeGbmBindings.sessionOpen()
// returns nullptr by design, so _open() returns before allocating a handle),
// so its wording is pinned by app_log_events_test.dart and the emit site
// itself by integration_test/repo_lifecycle_test.dart at device tier.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
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

List<String> _appMessages(RepoSessionController controller) {
  return controller.state.operationLog
      .whereType<AppLogEntry>()
      .map((AppLogEntry e) => e.message)
      .toList(growable: false);
}

FakeRepoSessionController _controller() {
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    const RepoSessionState(),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('checkout writes 「切分支」 to the log', () {
    test('a successful checkout names the branch', () {
      final FakeRepoSessionController controller = _controller();

      controller.debugRecordCheckout(target: 'feature/x');
      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': true,
        'kind': 'checkout',
      });

      expect(_appMessages(controller), <String>['Checked out feature/x']);
    });

    // A refused checkout already produces a git record carrying the reason.
    // Claiming HEAD moved when it did not is worse than saying nothing --
    // and this is exactly the shape that opens the checkout-recovery dialog,
    // so it is a live path, not a hypothetical one.
    test('a refused checkout writes nothing', () {
      final FakeRepoSessionController controller = _controller();

      controller.debugRecordCheckout(target: 'feature/x');
      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': false,
        'kind': 'checkout',
      });

      expect(_appMessages(controller), isEmpty);
    });
  });

  group('the gone marking writes page 10\'s warning row', () {
    test('one line per newly marked ref', () {
      final FakeRepoSessionController controller = _controller();

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/a', 'origin/b']),
      );

      expect(_appMessages(controller), <String>[
        'origin/a no longer exists on the remote; marked as gone (not pruned)',
        'origin/b no longer exists on the remote; marked as gone (not pruned)',
      ]);
      expect(
        controller.state.operationLog.whereType<AppLogEntry>().every(
          (AppLogEntry e) => e.level == OperationLogLevel.warning,
        ),
        isTrue,
      );
    });

    // The property that matters, and the reason _logNewlyGoneRefs diffs
    // instead of logging the whole preview: an automatic preview runs after
    // *every* fetch, so a ref that is still gone must not produce a fresh
    // warning each time until the user gets round to pruning it.
    test('a second preview of the same refs adds nothing', () {
      final FakeRepoSessionController controller = _controller();

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/a']),
      );
      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/a']),
      );

      expect(_appMessages(controller), hasLength(1));
    });

    test('a ref that appears in a later preview is logged then', () {
      final FakeRepoSessionController controller = _controller();

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/a']),
      );
      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/a', 'origin/b']),
      );

      expect(_appMessages(controller), hasLength(2));
      expect(_appMessages(controller).last, startsWith('origin/b '));
    });

    // gonePendingByRemote is per remote, so "already known" has to be judged
    // per remote too -- a shared set would swallow upstream/a because
    // origin/a was seen first.
    test('another remote is judged against its own known set', () {
      final FakeRepoSessionController controller = _controller();

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/a']),
      );
      controller.debugHandleEvent(
        _prunePreviewEvent('upstream', <String>['upstream/a']),
      );

      expect(_appMessages(controller), hasLength(2));
    });
  });

  group('prune writes 「prune 掉哪些 ref」', () {
    test('a successful prune names the refs it removed', () {
      final FakeRepoSessionController controller = _controller();

      controller.debugHandleEvent(
        _prunePreviewEvent('origin', <String>['origin/a', 'origin/b']),
      );
      controller.debugRecordPruneRemote(
        remoteName: 'origin',
        refs: <String>['origin/a'],
      );
      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': true,
        'kind': 'prune-remote',
      });

      expect(
        _appMessages(controller).last,
        'Pruned 1 remote-tracking ref on origin: origin/a',
      );
    });

    test('a failed prune writes nothing', () {
      final FakeRepoSessionController controller = _controller();

      controller.debugRecordPruneRemote(
        remoteName: 'origin',
        refs: <String>['origin/a'],
      );
      controller.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': false,
        'kind': 'prune-remote',
      });

      expect(_appMessages(controller), isEmpty);
    });
  });

  // LOGRULES' 保留 row caps the log, not each kind of entry separately: an
  // app event and a git record compete for the same 500 slots.
  test('app entries go through the same memory cap git records do', () {
    final FakeRepoSessionController controller = FakeRepoSessionController(
      _identity,
      const RepoSessionState(),
      maxOperationLogEntries: 3,
    );
    addTearDown(controller.dispose);

    controller.debugHandleEvent(
      _prunePreviewEvent('origin', <String>['a', 'b', 'c', 'd', 'e']),
    );

    expect(controller.state.operationLog, hasLength(3));
    expect(_appMessages(controller).first, startsWith('c '));
  });
}
