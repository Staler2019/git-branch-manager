// GbmCloneJobNative, the seam over gbm_clone_* (gbm_capi.h's "Clone job"
// block): what it hands the native side, what it hands back, and the close
// order [FLU-close-session-before-callable] requires of any callback.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/clone_job_native.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/git_version.dart';

import '../../support/fake_repo_session.dart';

typedef _Emit = void Function(
  Pointer<Void>,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Void>,
);

class _CloneBindings extends FakeGbmBindings {
  final Pointer<Void> handle = Pointer<Void>.fromAddress(0xC10E);
  bool refuse = false;
  String staged = '';
  int versionResult = 0;

  final List<String> calls = <String>[];
  String? url;
  String? dest;
  int? recurse;
  int? depth;
  Pointer<NativeFunction<GbmEventCallbackNative>>? callback;
  String? secret;
  int freed = 0;

  void emit(int type, String json) {
    final Uint8List bytes = utf8.encode(json);
    final Pointer<Uint8> p = malloc<Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    callback!.asFunction<_Emit>()(handle, type, p, bytes.length, nullptr);
  }

  @override
  CloneStartDart get cloneStart =>
      (
        Pointer<Utf8> u,
        Pointer<Utf8> d,
        int r,
        int dep,
        Pointer<NativeFunction<GbmEventCallbackNative>> cb,
        Pointer<Void> userData,
      ) {
        calls.add('start');
        url = u.toDartString();
        dest = d.toDartString();
        recurse = r;
        depth = dep;
        callback = cb;
        if (refuse) {
          staged =
              '{"code":1,"codeName":"InvalidArgument","message":"bad url",'
              '"detail":"","argv":[],"exitCode":0}';
          return nullptr;
        }
        return handle;
      };

  @override
  CloneCancelDart get cloneCancel => (Pointer<Void> job) {
    expect(job, handle);
    calls.add('cancel');
  };

  @override
  CloneProvideCredentialDart get cloneProvideCredential =>
      (Pointer<Void> job, Pointer<Utf8> s) {
        expect(job, handle);
        calls.add('provide');
        secret = s.toDartString();
      };

  @override
  CloneCancelCredentialDart get cloneCancelCredential => (Pointer<Void> job) {
    expect(job, handle);
    calls.add('cancelCredential');
  };

  @override
  CloneCloseDart get cloneClose => (Pointer<Void> job) {
    expect(job, handle);
    calls.add('close');
  };

  @override
  GitVersionJsonDart get gitVersionJson => () {
    staged = versionResult == 0 ? '{"major":2,"minor":39,"patch":5}' : '';
    return versionResult;
  };

  @override
  FreeEventPayloadDart get freeEventPayload => (Pointer<Uint8> p) {
    freed++;
    malloc.free(p);
  };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => utf8.encode(staged).length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy => (Pointer<Uint8> out, int n) {
    out.asTypedList(n).setAll(0, utf8.encode(staged));
  };
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('start hands url, destination, options and a callback across', () {
    final _CloneBindings b = _CloneBindings();
    final CloneJobStart result = GbmCloneJobNative(b).start(
      url: 'https://example.com/a.git',
      destPath: '/tmp/a',
      recurseSubmodules: true,
      depth: 1,
      onEvent: (_) {},
    );

    expect(result, isA<CloneJobStarted>());
    expect(b.url, 'https://example.com/a.git');
    expect(b.dest, '/tmp/a');
    expect(b.recurse, 1);
    expect(b.depth, 1);
    expect(b.callback, isNot(nullptr));
  });

  test('recurse off is 0', () {
    final _CloneBindings b = _CloneBindings();
    GbmCloneJobNative(b).start(
      url: 'u',
      destPath: '/tmp/a',
      recurseSubmodules: false,
      depth: 0,
      onEvent: (_) {},
    );
    expect(b.recurse, 0);
    expect(b.depth, 0);
  });

  test('a refusal comes back as the staged GitError', () {
    final _CloneBindings b = _CloneBindings()..refuse = true;
    final CloneJobStart result = GbmCloneJobNative(b).start(
      url: '-x',
      destPath: '/tmp/a',
      recurseSubmodules: false,
      depth: 0,
      onEvent: (_) {},
    );
    expect(result, isA<CloneJobRefused>());
    expect((result as CloneJobRefused).error.codeName, 'InvalidArgument');
  });

  test('events reach onEvent and every payload is freed', () async {
    final _CloneBindings b = _CloneBindings();
    final List<GbmEvent> seen = <GbmEvent>[];
    final CloneJobStarted started = GbmCloneJobNative(b).start(
      url: 'u',
      destPath: '/tmp/a',
      recurseSubmodules: false,
      depth: 0,
      onEvent: seen.add,
    ) as CloneJobStarted;

    b.emit(GbmEventType.cloneProgress, '{"phase":"receiving"}');
    b.emit(GbmEventType.cloneFinished, '{"ok":true}');
    await _settle();

    expect(seen.map((GbmEvent e) => e.type), <int>[
      GbmEventType.cloneProgress,
      GbmEventType.cloneFinished,
    ]);
    expect(utf8.decode(seen.first.payload!), '{"phase":"receiving"}');
    expect(b.freed, 2);
    started.job.close();
  });

  test('cancel and the credential answers forward to the job', () {
    final _CloneBindings b = _CloneBindings();
    final CloneJobHandle job = (GbmCloneJobNative(b).start(
      url: 'u',
      destPath: '/tmp/a',
      recurseSubmodules: false,
      depth: 0,
      onEvent: (_) {},
    ) as CloneJobStarted).job;

    job.provideCredential('s3cret');
    job.cancelCredential();
    job.cancel();
    job.close();

    expect(b.secret, 's3cret');
    expect(b.calls, <String>[
      'start',
      'provide',
      'cancelCredential',
      'cancel',
      'close',
    ]);
  });

  // [FLU-close-session-before-callable]: gbm_clone_close joins the job's
  // thread, after which nothing emits; only then may the callable go.
  test('close closes the native job, then the callable, once', () async {
    final _CloneBindings b = _CloneBindings();
    final CloneJobHandle job = (GbmCloneJobNative(b).start(
      url: 'u',
      destPath: '/tmp/a',
      recurseSubmodules: false,
      depth: 0,
      onEvent: (_) {},
    ) as CloneJobStarted).job;

    job.close();
    job.close();
    await _settle();

    expect(b.calls.where((String c) => c == 'close').length, 1);
    expect((job as GbmCloneJob).events.isNativeCallbackClosed, isTrue);
    // A call after close never reaches a released job.
    job.cancel();
    expect(b.calls.where((String c) => c == 'cancel'), isEmpty);
  });

  test('gitVersion reads gbm_git_version_json, null when no git', () {
    final _CloneBindings b = _CloneBindings();
    expect(GbmCloneJobNative(b).gitVersion(), const GitVersion(2, 39, 5));
    b.versionResult = -2;
    expect(GbmCloneJobNative(b).gitVersion(), isNull);
  });
}
