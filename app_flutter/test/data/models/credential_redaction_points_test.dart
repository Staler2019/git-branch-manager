// The masking's three application points (security review P3-F): every
// credential a URL carries is masked where it enters Dart, so the drawer,
// Copy All, Save As and any future exporter all start from masked text.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_action.dart';
import 'package:gbm_flutter/data/models/app_action_cancel_token.dart';
import 'package:gbm_flutter/data/models/app_action_outcome.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/services/app_action_runner.dart';

const String _secretUrl = 'https://alice:s3cret@example.invalid/r.git';
const String _maskedUrl = 'https://alice:••••@example.invalid/r.git';

Map<String, dynamic> _recordJson({
  required List<String> argv,
  String commandLine = '',
  String stderrText = '',
}) => <String, dynamic>{
  'id': 1,
  'running': false,
  'whenEpochMs': 0,
  'repoDir': '/repo',
  'argv': argv,
  'commandLine': commandLine,
  'exitCode': 128,
  'durationMs': 1,
  'stderrText': stderrText,
  'cancelled': false,
  'timedOut': false,
  'benignExit': false,
  'timeoutMs': 0,
  'idleTimeoutMs': 0,
};

void main() {
  group('OperationRecord.fromJson', () {
    test('masks argv and stderr', () {
      final OperationRecord record = OperationRecord.fromJson(
        _recordJson(
          argv: <String>['git', 'clone', '--', _secretUrl, '/tmp/r'],
          stderrText: "fatal: unable to access '$_secretUrl/': 403",
        ),
      );
      expect(record.argv, <String>['git', 'clone', '--', _maskedUrl, '/tmp/r']);
      expect(record.stderrText, "fatal: unable to access '$_maskedUrl/': 403");
    });

    test(
      'rebuilds the command line from the masked argv, ignoring the wire',
      () {
        final OperationRecord record = OperationRecord.fromJson(
          _recordJson(
            argv: <String>['git', 'clone', _secretUrl],
            commandLine: 'git clone $_secretUrl',
          ),
        );
        expect(record.commandLine, 'git clone $_maskedUrl');
        expect(record.message, isNot(contains('s3cret')));
      },
    );

    // Logging.cpp's OperationRecord::commandLine(): quote an argument that
    // is empty or holds any of ` \t"'\$*?`, escaping `"` and `\`.
    for (final (String name, List<String> argv, String line)
        in <(String, List<String>, String)>[
          ('plain', <String>['git', 'status'], 'git status'),
          ('empty', <String>['git', 'commit', '-m', ''], 'git commit -m ""'),
          ('space', <String>['git', 'add', 'a b'], 'git add "a b"'),
          ('tab', <String>['x', 'a\tb'], 'x "a\tb"'),
          ('double quote', <String>['x', 'say "hi"'], r'x "say \"hi\""'),
          ('single quote', <String>['x', "it's"], 'x "it\'s"'),
          ('backslash', <String>['x', r'C:\a'], r'x "C:\\a"'),
          ('dollar', <String>['x', r'$HOME'], r'x "$HOME"'),
          ('glob', <String>['x', '*.txt', 'a?'], 'x "*.txt" "a?"'),
          ('format arg', <String>['git', '--format=%H'], 'git --format=%H'),
        ]) {
      test('command line quoting: $name', () {
        expect(
          OperationRecord.fromJson(_recordJson(argv: argv)).commandLine,
          line,
        );
      });
    }
  });

  test('GitError.fromJson masks message, detail and argv', () {
    final GitError error = GitError.fromJson(<String, dynamic>{
      'code': 1,
      'codeName': 'CommandFailed',
      'message': 'Could not reach $_secretUrl',
      'detail': "fatal: repository '$_secretUrl' not found",
      'argv': <String>['git', 'fetch', _secretUrl],
      'exitCode': 128,
    });
    expect(error.message, 'Could not reach $_maskedUrl');
    expect(error.detail, "fatal: repository '$_maskedUrl' not found");
    expect(error.argv, <String>['git', 'fetch', _maskedUrl]);
  });

  test('AppActionRunner masks the message it logs and returns', () async {
    final List<AppLogEntry> lines = <AppLogEntry>[];
    final AppActionOutcome<void> outcome = await const AppActionRunner().run(
      AppAction<void>(
        name: 'cloneRepository',
        cancellable: false,
        body: (_) async => throw const FormatException('x'),
        describeSuccess: (_) => 'Cloned $_secretUrl',
        describeFailure: (_) => 'Could not clone $_secretUrl',
        describeCancelled: () => 'Cancelled clone of $_secretUrl',
      ),
      sink: lines.add,
    );
    expect(outcome.message, 'Could not clone $_maskedUrl');
    expect(lines.single.message, 'Could not clone $_maskedUrl');
  });

  group('AppActionRunner masks every path, not only failure', () {
    AppAction<int> action(Future<int> Function() body) => AppAction<int>(
      name: 'cloneRepository',
      cancellable: true,
      body: (_) => body(),
      describeSuccess: (_) => 'Cloned $_secretUrl',
      describeFailure: (_) => 'Could not clone $_secretUrl',
      describeCancelled: () => 'Cancelled clone of $_secretUrl',
    );

    test('success', () async {
      final List<AppLogEntry> lines = <AppLogEntry>[];
      final AppActionOutcome<int> outcome = await const AppActionRunner().run(
        action(() async => 1),
        sink: lines.add,
      );
      expect(outcome.message, 'Cloned $_maskedUrl');
      expect(lines.single.message, 'Cloned $_maskedUrl');
    });

    test('cancelled', () async {
      final List<AppLogEntry> lines = <AppLogEntry>[];
      final AppActionOutcome<int> outcome = await const AppActionRunner().run(
        action(() async => 1),
        sink: lines.add,
        token: AppActionCancelToken()..cancel(),
      );
      expect(outcome.message, 'Cancelled clone of $_maskedUrl');
      expect(lines.single.message, 'Cancelled clone of $_maskedUrl');
    });
  });
}
