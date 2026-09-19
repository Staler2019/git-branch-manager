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

/// A clock reading [age] after [entry]'s real modification time.
///
/// Dart's [Directory] has no mtime setter -- only [File] does, and on Windows
/// even `File.setLastModified` refuses a directory (measured, errno 50) -- so
/// the age guard cannot be exercised by aging the entry. Only the difference
/// between `now` and the entry's mtime decides anything, so the clock moves
/// instead, and no `touch` (or its local-time argument format) is needed.
DateTime Function() _clockAfter(FileSystemEntity entry, Duration age) {
  final DateTime at = entry.statSync().modified.add(age);
  return () => at;
}

/// Makes `deleteSync(recursive: true)` on [dir] fail for this user, and returns
/// what puts it back so the fixture can be removed afterwards.
///
/// The mechanism is the OS's own, so it is chosen per OS. POSIX refuses to
/// remove an entry from a directory the user cannot write, which is `chmod
/// 555`. That means nothing to NTFS; what Windows refuses instead is deleting
/// a tree that holds a file another handle has open (ERROR_SHARING_VIOLATION,
/// errno 32 -- measured: `deleteSync(recursive: true)` throws). POSIX has the
/// opposite rule, so neither mechanism is portable, and a `chmod` that
/// silently does nothing would leave the test below passing without ever
/// having met a delete that fails.
void Function() _makeUndeletable(Directory dir) {
  if (Platform.isWindows) {
    final RandomAccessFile held = File(
      '${dir.path}/held',
    ).openSync(mode: FileMode.write);
    return held.closeSync;
  }
  Directory('${dir.path}/inner').createSync();
  Process.runSync('chmod', <String>['555', dir.path]);
  return () {
    Process.runSync('chmod', <String>['u+w', dir.path]);
  };
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
      final Directory backup = Directory('${f.target.path}.gbm-old')
        ..createSync(recursive: true);
      addTearDown(_makeUndeletable(backup));

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

        await f.installer.sweepUpdateLeftovers(
          tempDir: f.temp,
          now: _clockAfter(stale, const Duration(days: 2)),
        );

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

        await f.installer.sweepUpdateLeftovers(
          tempDir: f.temp,
          now: _clockAfter(fresh, const Duration(minutes: 5)),
        );

        expect(fresh.existsSync(), isTrue);
      });

      test('leaves unrelated temp directories alone', () async {
        final f = _fixture();
        final Directory other = Directory('${f.temp.path}/some-other-tool')
          ..createSync();
        final File loose = File('${f.temp.path}/gbm-update-not-a-dir')
          ..writeAsStringSync('x');

        await f.installer.sweepUpdateLeftovers(
          tempDir: f.temp,
          now: _clockAfter(other, const Duration(days: 30)),
        );

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
