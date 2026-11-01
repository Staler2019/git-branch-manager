// A commit that renamed a file lists it once, under its new name, with the
// old name beside it. Clicking that row has to ask for the diff with both
// names: with the new one alone git never sees the deleted half and the diff
// pane draws the whole file as added. Integration tier, because the old path
// is looked up by ChangedFilesPanel against the provider's file list -- a
// ChangedFilesPanelCore widget test only sees the callback's path.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/routing/route_paths.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/changed-file-rename-repo',
  gitDir: '/test/changed-file-rename-repo/.git',
);

const Signature _signature = Signature(
  name: 'Test Author',
  email: 'author@example.com',
  when: 0,
  tzOffsetMinutes: 0,
);

ChangedFile _file(String path, {String oldPath = '', FileChangeKind? kind}) =>
    ChangedFile(
      path: path,
      oldPath: oldPath,
      kind: kind ?? FileChangeKind.modified,
      oldMode: '100644',
      newMode: '100644',
      oldBlob: 'aaa',
      newBlob: 'bbb',
      similarity: kind == FileChangeKind.renamed ? 100 : 0,
      addedLines: 1,
      removedLines: 1,
    );

Future<PumpedWorkspace> _pump(WidgetTester tester) async {
  final RepoSessionState state = RepoSessionState(
    isOpen: true,
    commitFiles: <ChangedFile>[
      _file('moved.dart', oldPath: 'origin.dart', kind: FileChangeKind.renamed),
      _file('edited.dart'),
    ],
    commitMetaCache: const <String, CommitMeta>{
      'abc123': CommitMeta(
        oid: 'abc123',
        tree: 'tree123',
        parents: <String>[],
        author: _signature,
        committer: _signature,
        subject: 'Move a file',
        body: '',
        signedCommit: false,
      ),
    },
  );
  final PumpedWorkspace pumped = await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: state,
    overrides: <Override>[
      selectedCommitProvider(_identity).overrideWith((ref) => 'abc123'),
    ],
    historyBuilder: (context, state) => HistoryPage(identity: _identity),
  );
  pumped.router.go(
    RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
  );
  await tester.pumpAndSettle();
  return pumped;
}

List<FakeCommand> _diffRequests(PumpedWorkspace pumped) => pumped
    .controller
    .commandLog
    .where((FakeCommand c) => c.name == 'requestCommitFileDiff')
    .toList(growable: false);

void main() {
  testWidgets('clicking a renamed file asks for its diff with the old name', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);

    await tester.tap(find.text('moved.dart'));
    // pump, not pumpAndSettle: the diff never arrives from the fake, so the
    // panel sits on its loading spinner ([TEST-no-pumpandsettle-with-spinner]).
    await tester.pump();

    final List<FakeCommand> requests = _diffRequests(pumped);
    expect(requests, hasLength(1));
    expect(requests.single.args['oid'], 'abc123');
    expect(requests.single.args['path'], 'moved.dart');
    expect(requests.single.args['oldPath'], 'origin.dart');
  });

  testWidgets('clicking a file that was not renamed sends no old name', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);

    await tester.tap(find.text('edited.dart'));
    // pump, not pumpAndSettle: the diff never arrives from the fake, so the
    // panel sits on its loading spinner ([TEST-no-pumpandsettle-with-spinner]).
    await tester.pump();

    final List<FakeCommand> requests = _diffRequests(pumped);
    expect(requests, hasLength(1));
    expect(requests.single.args['oldPath'], '');
  });
}
