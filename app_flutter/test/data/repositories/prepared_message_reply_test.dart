// GBM_EVENT_PREPARED_MESSAGE_READY into RepoSessionState.preparedMessage.
// A failed read must be distinguishable from a successful empty one: the
// Working Copy box replaces its text on a reply, and an empty "success" would
// clear it (prepared-commit-message plan, REVISE #4). The request side needs
// an open session, which the fake seam cannot give; the device tier
// (prepared_message_flow_test.dart) drives it for real.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

GbmEvent _ready(Map<String, dynamic> payload) => GbmEvent(
  GbmEventType.preparedMessageReady,
  utf8.encode(jsonEncode(payload)),
);

RepoSessionController _controller() => RepoSessionController(
  FakeGbmBindings(),
  _identity,
  FakeRecentsRepository(),
);

void main() {
  test('a successful reply is stored as not failed', () {
    final RepoSessionController c = _controller();
    addTearDown(c.dispose);

    c.debugHandleEvent(
      _ready(<String, dynamic>{'message': "Merge branch 'x'"}),
    );

    expect(c.state.preparedMessage?.message, "Merge branch 'x'");
    expect(c.state.preparedMessage?.failed, isFalse);
  });

  test('a reply carrying an error is failed, unlike an empty success', () {
    final RepoSessionController c = _controller();
    addTearDown(c.dispose);

    c.debugHandleEvent(
      _ready(<String, dynamic>{
        'message': '',
        'error': <String, dynamic>{'code': 1, 'message': 'boom'},
      }),
    );
    expect(c.state.preparedMessage?.failed, isTrue);

    c.debugHandleEvent(_ready(<String, dynamic>{'message': ''}));
    expect(c.state.preparedMessage?.failed, isFalse);
  });
}
