import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';

/// Keeps a checked-in copy of the generated PowerShell updater in step with
/// the generator.
///
/// The `.ps1` is the one artefact of this feature that no tier here can run:
/// this machine is Linux, `ci.yml`'s Flutter job is ubuntu-only, and
/// `windows/runner/` compiles solely on a release tag (#69). A syntax error
/// in it would therefore reach a user before it reached anyone else -- and
/// it would arrive as "the app closed and never came back", because a
/// PowerShell parse failure happens before the script's first line and so
/// before it can write a single word of its own transcript.
///
/// `cq.yml`'s `powershell-parse` job closes that gap by parsing this file on
/// a `windows-latest` runner. It parses the golden rather than generating
/// the script itself, which keeps a whole Flutter toolchain off the Windows
/// runner; the chain that makes that sound is:
///
/// 1. change the generator without regenerating → this test fails on Linux;
/// 2. regenerate → any syntax error is carried into the golden verbatim;
/// 3. the Windows job parses the golden → the error surfaces there.
///
/// So the golden cannot silently drift, and a lazily regenerated one is not
/// a hole: carrying the mistake forward is exactly what makes step 3 catch
/// it.
///
/// Regenerate with:
///
/// ```
/// GBM_UPDATE_GOLDEN=1 flutter test test/data/services/update_script_golden_test.dart
/// ```
void main() {
  // Fixed, and deliberately not a temp path: the golden has to be identical
  // on every machine, and `installTarget()` derives the target from the
  // executable. Both are POSIX-shaped because `installTarget()` splits on
  // the *host's* separator -- the same reason every other Windows test here
  // injects a POSIX `executablePath`. The script only ever quotes them as
  // literals, so their shape does not change what is being parsed.
  const String executable = '/opt/gbm-example/gbm_flutter.exe';
  const String staged = '/tmp/gbm-update-example/payload';

  test('the generated Windows updater matches the checked-in golden', () async {
    final Directory scriptDir = Directory.systemTemp.createTempSync(
      'gbm-update-golden',
    );
    addTearDown(() => scriptDir.deleteSync(recursive: true));

    await UpdateInstaller(
      operatingSystem: 'windows',
      executablePath: executable,
      systemRoot: r'C:\Windows',
      exitProcess: (int code) {},
      armWatchdog: (Duration after) async => true,
      start: (String e, List<String> a, {String? workingDirectory}) async =>
          const DetachedStart.ok(),
    ).launchUpdater(
      staged: Directory(staged),
      scriptDir: scriptDir,
      processId: 4242,
      beforeExit: () async {},
    );

    // Read as bytes, not as a string: the BOM is half of what is being
    // pinned. `powershell.exe` reads a BOM-less .ps1 as ANSI, which
    // mojibakes every path baked into it, and a string comparison would
    // silently normalise that away.
    final List<int> generated = File(
      '${scriptDir.path}${Platform.pathSeparator}gbm-update.ps1',
    ).readAsBytesSync();

    final File golden = File('test/fixtures/gbm-update.ps1.golden');
    if (Platform.environment['GBM_UPDATE_GOLDEN'] == '1') {
      golden.writeAsBytesSync(generated);
    }

    expect(
      golden.existsSync(),
      isTrue,
      reason: 'run with GBM_UPDATE_GOLDEN=1 to create it',
    );
    expect(
      generated,
      golden.readAsBytesSync(),
      reason:
          'the generator changed; regenerate with GBM_UPDATE_GOLDEN=1 so '
          "cq.yml's windows-latest job parses what actually ships",
    );
  });

  test('the golden really carries the BOM the Windows path depends on', () {
    expect(
      File('test/fixtures/gbm-update.ps1.golden').readAsBytesSync().take(3),
      <int>[0xEF, 0xBB, 0xBF],
    );
  });
}
