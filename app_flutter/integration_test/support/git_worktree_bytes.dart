// What git itself writes to a working tree for a given content, on this
// machine. The device tier asserts on files the app rewrote *through git*
// (a line discard is `git apply -R`), and git converts line endings on the
// way out according to core.autocrlf / core.eol / .gitattributes. Git for
// Windows installs `core.autocrlf=true` system-wide, so the same discard
// writes `alpha\r\n` there and `alpha\n` on macOS. A literal expectation is
// right on one machine only; asking git is right on every one, without
// switching off the setting the user's real repositories run with.
import 'dart:convert';
import 'dart:io';

/// The text git would write at [filePath] in [repoPath] for [lfContent]
/// (written with `\n` line ends), under this machine's real git config.
///
/// Stores [lfContent] unfiltered as a blob, then lets `cat-file --filters`
/// apply the checkout-side conversion for that path -- the same smudge a
/// `git apply`/`checkout` performs. Leaves one unreachable loose object.
///
/// Runs a dart:io `Process`: call it before the app opens or after it has
/// settled, never while the app is running git
/// ([TEST-no-dart-process-while-core-runs-git]).
String expectedWorktreeText(
  String repoPath,
  String filePath,
  String lfContent,
) {
  final Directory tmp = Directory.systemTemp.createTempSync('gbm_e2e_blob_');
  try {
    final File source = File('${tmp.path}/content')
      ..writeAsBytesSync(utf8.encode(lfContent));
    final String oid = _git(repoPath, <String>[
      'hash-object',
      '-w',
      '--no-filters',
      source.path,
    ]).trim();
    return _git(repoPath, <String>[
      'cat-file',
      '--filters',
      '--path=$filePath',
      oid,
    ]);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// `git` with stdout decoded as UTF-8 and nothing else: `\r` must survive.
String _git(String repoPath, List<String> args) {
  final ProcessResult result = Process.runSync(
    'git',
    args,
    workingDirectory: repoPath,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      'exit ${result.exitCode} in $repoPath:\n${result.stderr}',
      result.exitCode,
    );
  }
  return result.stdout as String;
}
