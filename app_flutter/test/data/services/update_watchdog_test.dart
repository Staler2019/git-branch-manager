// The watchdog's whole claim is about a *blocked* main isolate: `exit()` from
// a spawned isolate ends the VM while the main one is still inside a
// synchronous call. No fake-async test can block a real event loop
// ([TEST-fixture-cannot-disagree] shape 11), so this runs the real entry
// point in a separate `dart` process whose main isolate sleeps synchronously
// for longer than the test would wait.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _script = '''
import 'dart:io';
import 'dart:isolate';

import 'package:gbm_flutter/data/services/update_watchdog.dart';

Future<void> main() async {
  await Isolate.spawn(updateWatchdogEntryPoint, 200);
  sleep(const Duration(seconds: 30));
  exit(7);
}
''';

void main() {
  test(
    'the watchdog ends the process while the main isolate is blocked',
    () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'gbm-watchdog-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final File script = File('${dir.path}/watchdog_probe.dart')
        ..writeAsStringSync(_script);
      final String packages = File('.dart_tool/package_config.json')
          .absolute
          .path;

      final Stopwatch clock = Stopwatch()..start();
      final ProcessResult result = await Process.run('dart', <String>[
        '--packages=$packages',
        script.path,
      ], runInShell: Platform.isWindows);
      clock.stop();

      expect(
        result.exitCode,
        0,
        reason:
            'exit 7 means the main isolate woke up first: the watchdog never '
            'ended the process.\nstderr: ${result.stderr}',
      );
      expect(clock.elapsed, lessThan(const Duration(seconds: 20)));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
