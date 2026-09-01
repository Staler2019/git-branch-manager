import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';

/// The transcript both halves of the handover write.
///
/// Its whole reason for existing is that the *app* side of an install used
/// to write nothing anywhere: the log had one writer, the generated updater
/// script, and every failure before that script was started -- a corrupt
/// archive, a shell that would not launch, a session close that never
/// returned -- left a `gbm-update.ps1` on disk with no `gbm-update.log`
/// beside it and an app still on screen. That is the Windows report this
/// round came from.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('gbm-update-log');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  UpdateLog logIn(Directory dir) => UpdateLog(dir);

  test('lives beside the updater script', () {
    expect(
      logIn(root).file.path,
      '${root.path}${Platform.pathSeparator}$kUpdateLogName',
    );
  });

  // Truncation moved here from the scripts. The reason for truncating at all
  // is unchanged -- a transcript accumulating every update ever run would
  // bury the one being asked about -- but doing it at the *start* of the
  // attempt means nothing written afterwards is lost, where doing it in the
  // script deleted the app's half every time.
  test('begin starts a fresh transcript', () {
    final UpdateLog log = logIn(root)..write('FROM AN OLDER UPDATE');
    log.begin('installing 1.2.3');

    final String contents = log.file.readAsStringSync();
    expect(contents, contains('installing 1.2.3'));
    expect(contents, isNot(contains('OLDER UPDATE')));
  });

  test('write appends rather than replacing', () {
    final UpdateLog log = logIn(root)..begin('installing 1.2.3');
    log.write('unpacking');
    log.write('exiting');

    final List<String> lines = log.file.readAsLinesSync();
    expect(lines, hasLength(3));
    expect(lines[0], endsWith('installing 1.2.3'));
    expect(lines[1], endsWith('unpacking'));
    expect(lines[2], endsWith('exiting'));
  });

  // Second precision and no fractional part, so the app's lines and the
  // script's `Get-Date -Format s` / `date '+%Y-%m-%dT%H:%M:%S'` lines below
  // them read as one column rather than two formats in one file.
  test('stamps each line the way the scripts do', () {
    final UpdateLog log = logIn(root)..begin('installing 1.2.3');

    expect(
      log.file.readAsLinesSync().single,
      matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} installing ')),
    );
  });

  // Losing the transcript must never be what fails an update, so every
  // method swallows. A directory that does not exist stands in for the whole
  // family -- a read-only temp, a full disk, an unmounted volume -- because
  // it is the one shape that fails identically for every user, root
  // included, where a `chmod 555` fixture is simply ignored for uid 0.
  test('never throws when the directory is not there', () {
    final UpdateLog log = logIn(Directory('${root.path}/gone/deeper'));

    expect(() => log.begin('installing 1.2.3'), returnsNormally);
    expect(() => log.write('unpacking'), returnsNormally);
    expect(log.file.existsSync(), isFalse);
  });
}
