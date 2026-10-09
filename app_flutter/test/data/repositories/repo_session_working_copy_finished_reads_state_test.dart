// A commit is a working-copy operation, so it finishes on
// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED rather than OPERATION_FINISHED --
// and that handler used to leave RepoState alone. Committing a merge from the
// Working Copy box therefore left `isMerging` (and the banner) true until the
// next focus or F5. The reducer must re-read RepoState on this event too.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

Map<String, dynamic> _repoStateJson({required int flags}) => <String, dynamic>{
  'flags': flags,
  'isClean': flags == 0,
  'isSequencerOperation': false,
  'rebaseStep': 0,
  'rebaseTotal': 0,
  'rebaseOntoLabel': '',
  'indexLocked': false,
  'indexLockAgeSeconds': null,
  'preparedMessagePending': false,
  'describe': '',
};

/// Serves whatever [current] holds as the RepoState staging buffer, so a test
/// can change what core "has on disk" between two events.
class _RepoStateBindings extends FakeGbmBindings {
  Map<String, dynamic> current = _repoStateJson(flags: RepoStateFlags.merge);
  Uint8List _staged = Uint8List(0);

  @override
  RepoStateJsonDart get repoStateJson => (Pointer<Void> session) {
    _staged = utf8.encode(jsonEncode(current));
    return 0;
  };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _staged.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) {
        out.asTypedList(outLen).setAll(0, _staged);
      };
}

GbmEvent _commitFinished() => GbmEvent(
  GbmEventType.workingCopyOperationFinished,
  utf8.encode(
    jsonEncode(<String, dynamic>{'kind': 'commit', 'succeeded': true}),
  ),
);

void main() {
  test('a finished commit re-reads RepoState, so a concluded merge ends', () {
    final _RepoStateBindings bindings = _RepoStateBindings();
    final RepoSessionController c = RepoSessionController(
      bindings,
      _identity,
      FakeRecentsRepository(),
    );
    addTearDown(c.dispose);
    // Arrange: a merge is in progress, as the last OPERATION_FINISHED left it.
    c.debugHandleEvent(const GbmEvent(GbmEventType.operationFinished, null));
    expect(c.state.repoState?.isMerging, isTrue);

    // Act: the commit concludes the merge on disk, then reports back.
    bindings.current = _repoStateJson(flags: 0);
    c.debugHandleEvent(_commitFinished());

    // Assert
    expect(c.state.repoState?.isMerging, isFalse);
  });
}
