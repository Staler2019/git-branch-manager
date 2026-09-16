// The focus-regain timing readout (fix/refresh-ui-first-tiering, C1) -- see
// [RefreshTimings]'s own doc comment for why every stamp but `focusAt` is
// "first one wins" rather than last-write-wins.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

GbmEvent _diffReadyEvent(String path, {required bool staged}) => GbmEvent(
  GbmEventType.workingCopyDiffReady,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'path': path,
      'staged': staged,
      'diff': <String, dynamic>{
        'files': <dynamic>[],
        'truncated': false,
        'inputBytes': 0,
      },
    }),
  ),
);

void main() {
  FakeRepoSessionController controller() {
    final FakeRepoSessionController c = FakeRepoSessionController(
      _identity,
      const RepoSessionState(isOpen: true),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('RepoSessionController.refreshTimings', () {
    test('refreshRepoStatus() resets to a fresh focusAt', () {
      final FakeRepoSessionController c = controller();
      c.publishRefs(RefSnapshot.empty);
      expect(c.state.refreshTimings.refsAt, isNotNull);

      c.refreshRepoStatus();

      expect(c.state.refreshTimings.focusAt, isNotNull);
      expect(
        c.state.refreshTimings.refsAt,
        isNull,
        reason: 'a fresh sweep must not carry a stamp from the last one',
      );
    });

    test('publishRefs stamps refsAt once, not on a later republish', () {
      final FakeRepoSessionController c = controller();
      c.refreshRepoStatus();

      c.publishRefs(RefSnapshot.empty);
      final DateTime? first = c.state.refreshTimings.refsAt;
      expect(first, isNotNull);

      c.publishRefs(RefSnapshot.empty);
      expect(c.state.refreshTimings.refsAt, first);
    });

    test('publishWorkingCopyStatus stamps statusAt once', () {
      final FakeRepoSessionController c = controller();
      c.refreshRepoStatus();

      c.publishWorkingCopyStatus(WorkingCopyStatus.empty);
      final DateTime? first = c.state.refreshTimings.statusAt;
      expect(first, isNotNull);

      c.publishWorkingCopyStatus(WorkingCopyStatus.empty);
      expect(c.state.refreshTimings.statusAt, first);
    });

    test('the first workingCopyDiffReady of a sweep stamps firstDiffAt, a '
        'second file does not move it', () {
      final FakeRepoSessionController c = controller();
      c.refreshRepoStatus();

      c.debugHandleEvent(_diffReadyEvent('a.txt', staged: false));
      final DateTime? first = c.state.refreshTimings.firstDiffAt;
      expect(first, isNotNull);

      c.debugHandleEvent(_diffReadyEvent('b.txt', staged: true));
      expect(c.state.refreshTimings.firstDiffAt, first);
    });
  });
}
