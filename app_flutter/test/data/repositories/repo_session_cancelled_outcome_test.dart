// A user's Cancel is not a failure. Spec page 10 LOGRULES reserves error for
// an action that was refused; a cancelled operation still leaves a CANCELLED
// row in the log, but must not raise the error banner. A cancel core refuses
// (NotCancellable, 使用者裁定 「capi不行cancel會拋錯」) is the opposite case:
// it is how the user hears the operation was left running, so it is shown.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

/// Answers the RepoState read every outcome triggers.
class _OutcomeBindings extends FakeGbmBindings {
  Uint8List _staged = Uint8List(0);

  @override
  RepoStateJsonDart get repoStateJson => (Pointer<Void> session) {
    _staged = utf8.encode(
      jsonEncode(<String, dynamic>{
        'flags': 0,
        'isClean': true,
        'isSequencerOperation': false,
        'rebaseStep': 0,
        'rebaseTotal': 0,
        'rebaseOntoLabel': '',
        'indexLocked': false,
        'indexLockAgeSeconds': null,
        'preparedMessagePending': false,
        'describe': '',
      }),
    );
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

Map<String, dynamic> _error(String codeName) => <String, dynamic>{
  'code': 0,
  'codeName': codeName,
  'message': '$codeName message',
  'detail': '',
  'argv': <String>[],
  'exitCode': 0,
};

GbmEvent _event(int type, Map<String, dynamic> payload) =>
    GbmEvent(type, utf8.encode(jsonEncode(payload)));

RepoSessionController _controller() {
  final RepoSessionController c = RepoSessionController(
    _OutcomeBindings(),
    _identity,
    FakeRecentsRepository(),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test(
    'a cancelled working-copy operation (fetch/pull/push) raises no error',
    () {
      final RepoSessionController c = _controller();
      c.debugHandleEvent(
        _event(GbmEventType.workingCopyOperationFinished, <String, dynamic>{
          'succeeded': false,
          'error': _error('Cancelled'),
        }),
      );
      expect(c.state.lastError, isNull);
    },
  );

  test('a cancelled queued operation raises no error', () {
    final RepoSessionController c = _controller();
    c.debugHandleEvent(
      _event(GbmEventType.operationFinished, <String, dynamic>{
        'succeeded': false,
        'error': _error('Cancelled'),
        'choices': <Object>[],
        'summary': '',
      }),
    );
    expect(c.state.lastError, isNull);
  });

  test('a real working-copy failure still raises its error', () {
    // The control: the suppression is for Cancelled only.
    final RepoSessionController c = _controller();
    c.debugHandleEvent(
      _event(GbmEventType.workingCopyOperationFinished, <String, dynamic>{
        'succeeded': false,
        'error': _error('ProcessFailed'),
      }),
    );
    expect(c.state.lastError?.codeName, 'ProcessFailed');
  });

  test('a cancel core refused is shown', () {
    final RepoSessionController c = _controller();
    c.debugHandleEvent(
      _event(GbmEventType.errorOccurred, _error('NotCancellable')),
    );
    expect(c.state.lastError?.codeName, 'NotCancellable');
  });
}
