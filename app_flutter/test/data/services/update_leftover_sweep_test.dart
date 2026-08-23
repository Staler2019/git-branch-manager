import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';

/// Builds an installer whose install target is a throwaway directory, and
/// returns both so a test can put leftovers beside it.
({UpdateInstaller installer, Directory target, Directory temp}) _fixture() {
  final Directory root = Directory.systemTemp.createTempSync('gbm-sweep');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  final Directory target = Directory('${root.path}/opt/gbm')
    ..createSync(recursive: true);
  final Directory temp = Directory('${root.path}/tmp')..createSync();
  return (
    installer: UpdateInstaller(
      operatingSystem: 'linux',
      executablePath: '${target.path}/gbm_flutter',
      abi: Abi.linuxX64,
    ),
    target: target,
    temp: temp,
  );
}

DateTime _now() => DateTime.utc(2026, 8, 23, 12);

/// Dart's [Directory] has no mtime setter -- only [File] does -- so the age
/// guard can only be exercised through `touch`. Present on macOS and Linux,
/// which is every platform this suite runs on (`ci.yml`'s Flutter job is
/// ubuntu-only).
///
/// `touch -t` reads its argument as local time, so the instant is converted
/// first; `statSync().modified` comes back local too, and `isAfter`
/// compares absolute instants either way.
void _setMtime(Directory dir, DateTime at) {
  final DateTime local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final String stamp =
      '${local.year}${two(local.month)}${two(local.day)}'
      '${two(local.hour)}${two(local.minute)}.${two(local.second)}';
  final ProcessResult result = Process.runSync('touch', <String>[
    '-t',
    stamp,
    dir.path,
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}

void main() {
  group('UpdateInstaller.sweepUpdateLeftovers', () {
    test('removes the previous install kept for rollback', () async {
      final f = _fixture();
      final Directory backup = Directory('${f.target.path}.gbm-old')
        ..createSync(recursive: true);
      File('${backup.path}/gbm_flutter').writeAsStringSync('old');

      await f.installer.sweepUpdateLeftovers(tempDir: f.temp, now: _now);

      expect(backup.existsSync(), isFalse);
      // The install this process is running from is not a leftover.
      expect(f.target.existsSync(), isTrue);
    });

    test('does nothing when there is no backup', () async {
      final f = _fixture();

      await f.installer.sweepUpdateLeftovers(tempDir: f.temp, now: _now);

      expect(f.target.existsSync(), isTrue);
    });

    // Housekeeping must never be the reason the app fails to start. A
    // backup the user has made read-only, or one on a volume that has gone
    // away, is not this process's problem to report.
    test('survives a backup it cannot delete', () async {
      final f = _fixture();
      final Directory parent = Directory('${f.target.path}.gbm-old')
        ..createSync(recursive: true);
      Directory('${parent.path}/inner').createSync();
      Process.runSync('chmod', <String>['555', parent.path]);
      addTearDown(() {
        Process.runSync('chmod', <String>['u+w', parent.path]);
      });

      await expectLater(
        f.installer.sweepUpdateLeftovers(tempDir: f.temp, now: _now),
        completes,
      );
    });

    group('download directories', () {
      test('removes one left behind by an earlier update', () async {
        final f = _fixture();
        final Directory stale = Directory('${f.temp.path}/gbm-update-abc')
          ..createSync();
        File('${stale.path}/bundle.tar.gz').writeAsStringSync('x');
        _setMtime(stale, _now().subtract(const Duration(days: 2)));

        await f.installer.sweepUpdateLeftovers(tempDir: f.temp, now: _now);

        expect(stale.existsSync(), isFalse);
      });

      // A second instance may be downloading right now, into a directory
      // that looks exactly like a leftover. The age guard is the only thing
      // separating the two -- without it this sweep would delete another
      // instance's update mid-transfer.
      test('leaves a recent one alone', () async {
        final f = _fixture();
        final Directory fresh = Directory('${f.temp.path}/gbm-update-xyz')
          ..createSync();
        _setMtime(fresh, _now().subtract(const Duration(minutes: 5)));

        await f.installer.sweepUpdateLeftovers(tempDir: f.temp, now: _now);

        expect(fresh.existsSync(), isTrue);
      });

      test('leaves unrelated temp directories alone', () async {
        final f = _fixture();
        final Directory other = Directory('${f.temp.path}/some-other-tool')
          ..createSync();
        _setMtime(other, _now().subtract(const Duration(days: 30)));
        final File loose = File('${f.temp.path}/gbm-update-not-a-dir')
          ..writeAsStringSync('x')
          ..setLastModifiedSync(_now().subtract(const Duration(days: 30)));

        await f.installer.sweepUpdateLeftovers(tempDir: f.temp, now: _now);

        expect(other.existsSync(), isTrue);
        // A *file* with the prefix is not a download directory; deleting by
        // name alone would reach past what this sweep owns.
        expect(loose.existsSync(), isTrue);
      });

      test('survives a temp directory that does not exist', () async {
        final f = _fixture();

        await expectLater(
          f.installer.sweepUpdateLeftovers(
            tempDir: Directory('${f.temp.path}/gone'),
            now: _now,
          ),
          completes,
        );
      });
    });
  });
}
