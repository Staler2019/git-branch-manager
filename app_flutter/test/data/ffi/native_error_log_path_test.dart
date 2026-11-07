import 'dart:convert';
import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/ffi/native_error_events.dart';

import '../../support/fake_repo_session.dart';

/// Stages [staged] the way the library does, behind [status].
class _LogPathBindings extends FakeGbmBindings {
  _LogPathBindings(this.status, String staged) : _bytes = utf8.encode(staged);

  final int status;
  final List<int> _bytes;

  @override
  NativeErrorLogPathJsonDart get nativeErrorLogPathJson =>
      () => status;

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _bytes.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) =>
          out.asTypedList(outLen).setAll(0, _bytes.take(outLen));
}

void main() {
  test('reads the staged path', () {
    expect(
      readNativeErrorLogPath(
        _LogPathBindings(
          0,
          r'{"path":"C:\\Users\\me\\工作\\gbm-native-errors.log"}',
        ),
      ),
      r'C:\Users\me\工作\gbm-native-errors.log',
    );
  });

  test('a failed call reads as no path, whatever is staged', () {
    expect(
      readNativeErrorLogPath(_LogPathBindings(-1, '{"path":"/stale"}')),
      '',
    );
  });

  test('a staged object without a path reads as no path', () {
    expect(readNativeErrorLogPath(_LogPathBindings(0, '{}')), '');
  });
}
