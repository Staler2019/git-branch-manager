// A staged rename's diff header names both paths, whether or not the work
// tree has edited the file since. Spec:
// docs/claude-design-demo/rename-diff-display-spec.html, 畫面 2.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/working_copy_repository.dart'
    as wc;
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';
import 'package:gbm_flutter/widgets/gbm_diff_header_bar.dart';

import '../../support/fake_repo_session.dart';
import '../../support/pump_app.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

WorkingCopyEntry _entry({
  required String path,
  String oldPath = '',
  FileChangeKind indexStatus = FileChangeKind.modified,
  bool hasUnstagedChange = false,
}) => WorkingCopyEntry(
  path: path,
  oldPath: oldPath,
  untracked: false,
  staged: true,
  indexStatus: indexStatus,
  hasUnstagedChange: hasUnstagedChange,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: oldPath.isEmpty ? 0 : 100,
  isSubmodule: false,
  isConflicted: false,
);

Future<void> _pumpAndSelect(WidgetTester tester, WorkingCopyEntry entry) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    const RepoSessionState(),
  );
  await pumpGbmWidget(
    tester,
    child: SizedBox(
      width: 800,
      height: 600,
      child: WorkingCopyView(identity: _identity),
    ),
    overrides: [
      repoSessionProvider(_identity).overrideWith((ref) => fake),
      wc
          .repoWorkingCopyStatusProvider(_identity)
          .overrideWithValue(
            WorkingCopyStatus(entries: <WorkingCopyEntry>[entry]),
          ),
      wc
          .repoWorkingCopyDiffsProvider(_identity)
          .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
      wc
          .repoWorkingCopyFullDiffsProvider(_identity)
          .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
    ],
  );
  await tester.tap(find.text(entry.path).first);
  await tester.pump();
}

String _header(WidgetTester tester) =>
    tester.widget<GbmDiffHeaderBar>(find.byType(GbmDiffHeaderBar)).text;

void main() {
  testWidgets('a rename staged and nothing else names both paths', (
    tester,
  ) async {
    await _pumpAndSelect(
      tester,
      _entry(
        path: 'lib/b.dart',
        oldPath: 'lib/a.dart',
        indexStatus: FileChangeKind.renamed,
      ),
    );

    expect(_header(tester), 'lib/a.dart → lib/b.dart');
  });

  testWidgets('a rename staged then edited still names both paths', (
    tester,
  ) async {
    await _pumpAndSelect(
      tester,
      _entry(
        path: 'lib/b.dart',
        oldPath: 'lib/a.dart',
        indexStatus: FileChangeKind.renamed,
        hasUnstagedChange: true,
      ),
    );

    expect(_header(tester), 'lib/a.dart → lib/b.dart');
  });

  testWidgets('a staged edit names only its path', (tester) async {
    await _pumpAndSelect(tester, _entry(path: 'lib/c.dart'));

    expect(_header(tester), 'lib/c.dart');
  });
}
