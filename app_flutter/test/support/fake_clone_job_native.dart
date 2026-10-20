import 'dart:convert';
import 'dart:typed_data';

import 'package:gbm_flutter/data/ffi/clone_job_native.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/models/git_version.dart';

/// One fake clone job: records what the controller asked of it.
class FakeCloneJob implements CloneJobHandle {
  final List<String> calls = <String>[];

  @override
  void cancel() => calls.add('cancel');

  @override
  void provideCredential(String secret) => calls.add('provide:$secret');

  @override
  void cancelCredential() => calls.add('cancelCredential');

  @override
  void close() => calls.add('close');
}

/// A [CloneJobNative] that starts [FakeCloneJob]s and lets a test emit the
/// native events of job N by hand.
class FakeCloneJobNative implements CloneJobNative {
  FakeCloneJobNative({this.version = const GitVersion(2, 50, 1)});

  final GitVersion? version;
  final List<FakeCloneJob> jobs = <FakeCloneJob>[];
  final List<void Function(GbmEvent)> _sinks = <void Function(GbmEvent)>[];

  @override
  CloneJobStart start({
    required String url,
    required String destPath,
    required bool recurseSubmodules,
    required int depth,
    required void Function(GbmEvent event) onEvent,
  }) {
    final FakeCloneJob job = FakeCloneJob();
    jobs.add(job);
    _sinks.add(onEvent);
    return CloneJobStarted(job);
  }

  @override
  GitVersion? gitVersion() => version;

  void emit(int job, int type, Object json) => _sinks[job](
    GbmEvent(type, Uint8List.fromList(utf8.encode(jsonEncode(json)))),
  );
}
