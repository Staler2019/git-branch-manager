import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';

Map<String, dynamic> _json({required bool pending}) => <String, dynamic>{
  'flags': 0,
  'isClean': true,
  'isSequencerOperation': false,
  'rebaseStep': 0,
  'rebaseTotal': 0,
  'rebaseOntoLabel': '',
  'indexLocked': false,
  'indexLockAgeSeconds': null,
  'preparedMessagePending': pending,
  'describe': '',
};

void main() {
  test('preparedMessagePending is read from the wire, both ways', () {
    expect(
      RepoState.fromJson(_json(pending: true)).preparedMessagePending,
      isTrue,
    );
    expect(
      RepoState.fromJson(_json(pending: false)).preparedMessagePending,
      isFalse,
    );
  });

  test(
    'a payload without preparedMessagePending is rejected, not defaulted',
    () {
      // capi always sends it (JsonCodecTest); a missing key is a wire mismatch,
      // and defaulting it to false would hide one.
      final Map<String, dynamic> json = _json(pending: true)
        ..remove('preparedMessagePending');

      expect(() => RepoState.fromJson(json), throwsA(isA<TypeError>()));
    },
  );
}
