// Each column draws the status of its own side of the file: the staged column
// reads the index, the unstaged column the work tree. A file renamed in the
// index and then edited is a move on one side and a plain edit on the other.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/widgets/file_change_glyph.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

import '../../../support/pump_app.dart';

WorkingCopyEntry _entry({
  required String path,
  String oldPath = '',
  bool untracked = false,
  bool staged = false,
  FileChangeKind indexStatus = FileChangeKind.modified,
  bool hasUnstagedChange = false,
  FileChangeKind worktreeStatus = FileChangeKind.modified,
}) => WorkingCopyEntry(
  path: path,
  oldPath: oldPath,
  untracked: untracked,
  staged: staged,
  indexStatus: indexStatus,
  hasUnstagedChange: hasUnstagedChange,
  worktreeStatus: worktreeStatus,
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

final WorkingCopyEntry _movedThenEdited = _entry(
  path: 'lib/b.dart',
  oldPath: 'lib/a.dart',
  staged: true,
  indexStatus: FileChangeKind.renamed,
  hasUnstagedChange: true,
);
final WorkingCopyEntry _untracked = _entry(
  path: 'scratch.txt',
  untracked: true,
  hasUnstagedChange: true,
);
final WorkingCopyEntry _deletedInWorkTree = _entry(
  path: 'old.dart',
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.deleted,
);
final WorkingCopyEntry _stagedAdd = _entry(
  path: 'new.dart',
  staged: true,
  indexStatus: FileChangeKind.added,
);

Future<void> _pump(WidgetTester tester) => pumpGbmWidget(
  tester,
  child: SizedBox(
    width: 800,
    height: 600,
    child: WorkingCopyBoard(
      unstagedEntries: <WorkingCopyEntry>[
        _movedThenEdited,
        _untracked,
        _deletedInWorkTree,
      ],
      stagedEntries: <WorkingCopyEntry>[_movedThenEdited, _stagedAdd],
      onStageRequested: (_) {},
      onUnstageRequested: (_) {},
    ),
  ),
);

/// The glyph's icon name in the row keyed [rowKey], or null when the row
/// draws none.
String? _glyphIn(WidgetTester tester, String rowKey) {
  final Finder icon = find.descendant(
    of: find.descendant(
      of: find.byKey(Key(rowKey)),
      matching: find.byType(FileChangeGlyph),
    ),
    matching: find.byType(LucideIcon),
  );
  expect(
    find.descendant(
      of: find.byKey(Key(rowKey)),
      matching: find.byType(FileChangeGlyph),
    ),
    findsOneWidget,
    reason: rowKey,
  );
  return icon.evaluate().isEmpty ? null : tester.widget<LucideIcon>(icon).name;
}

void main() {
  testWidgets('a rename staged then edited is a move in the staged column '
      'and a plain edit in the unstaged one', (tester) async {
    await _pump(tester);

    expect(_glyphIn(tester, 'wc-file-staged-lib/b.dart'), 'move-right');
    expect(_glyphIn(tester, 'wc-file-unstaged-lib/b.dart'), isNull);
  });

  testWidgets('an untracked file is a plus', (tester) async {
    await _pump(tester);

    expect(_glyphIn(tester, 'wc-file-unstaged-scratch.txt'), 'plus');
  });

  testWidgets('a file deleted in the work tree is a minus', (tester) async {
    await _pump(tester);

    expect(_glyphIn(tester, 'wc-file-unstaged-old.dart'), 'minus');
  });

  testWidgets('a staged add is a plus', (tester) async {
    await _pump(tester);

    expect(_glyphIn(tester, 'wc-file-staged-new.dart'), 'plus');
  });

  testWidgets('the glyph comes before the file name', (tester) async {
    await _pump(tester);

    final Finder row = find.byKey(const Key('wc-file-staged-new.dart'));
    expect(
      tester
          .getRect(
            find.descendant(of: row, matching: find.byType(FileChangeGlyph)),
          )
          .right,
      lessThanOrEqualTo(
        tester
            .getRect(find.descendant(of: row, matching: find.text('new.dart')))
            .left,
      ),
    );
  });
}
