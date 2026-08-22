// The picker's *second* entry point: View -> Graph columns, which opens it in
// a `showDialog` Dialog rather than the History header's anchored popover.
//
// This had no coverage at any tier while the picker was rebuilt underneath it
// (`menu_bar_row_test.dart` only proves the menu item dispatches, against a
// hand-fed handler map). That is the shape this repo's audits keep finding --
// a working widget reached through a path nobody exercises -- and it matters
// more than usual here because the two carriers are not interchangeable: a
// Dialog imposes its own constraints on a shrink-wrapped ReorderableListView,
// and the route is pushed onto the root Navigator, so the same
// "does the ProviderScope still enclose it" question the popover raises
// applies again and is answered separately.
//
// It is also the *only* entry point on an empty repository: the History
// header button lives in `_CommitSearchField`, which is not rendered when
// there are no commits to filter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_columns_selector.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

Future<PumpedWorkspace> _openPicker(WidgetTester tester) async {
  final PumpedWorkspace pumped = await pumpWorkspace(
    tester,
    identity: _identity,
  );
  await tester.tap(find.text('View'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Graph columns'));
  await tester.pumpAndSettle();
  return pumped;
}

/// The grip at the trailing edge of the picker row labelled [label].
Finder _handle(String label) => find.descendant(
  of: find
      .ancestor(
        of: find.descendant(
          of: find.byType(GraphColumnsSelector),
          matching: find.text(label),
        ),
        matching: find.byType(Row),
      )
      .first,
  matching: find.byType(LucideIcon),
);

void main() {
  testWidgets('View > Graph columns opens the rebuilt picker in a Dialog', (
    tester,
  ) async {
    await _openPicker(tester);

    expect(find.byType(Dialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(GraphColumnsSelector),
      ),
      findsOneWidget,
    );
    // Spec's own labels, not the pre-rebuild "Hash"/"Changed Files" -- the
    // dialog and the popover must be showing the same widget, not a stale
    // copy of the old one.
    expect(find.text('Commit hash'), findsOneWidget);
    expect(find.text('Changed files'), findsOneWidget);
  });

  testWidgets('a toggle made in the Dialog reaches the shared notifier', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await _openPicker(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(GraphColumnsSelector),
        matching: find.text('Author'),
      ),
    );
    await tester.pumpAndSettle();

    // Read through the provider rather than the rows: WorkspaceScreen's
    // History child is a bare placeholder under pumpWorkspace, so the rows
    // are not what this entry point can be judged on. The claim is that the
    // root-Navigator Dialog still writes to the app's own container.
    expect(
      pumped.container.read(graphColumnVisibilityProvider)['author'],
      isFalse,
    );
  });

  testWidgets('the list still reorders inside the Dialog', (tester) async {
    // A shrink-wrapped ReorderableListView is laid out by whatever encloses
    // it, and a Dialog is not the popover's SingleChildScrollView. Dragging
    // is the one interaction that could plausibly differ between the two
    // carriers, so it is asserted on this one rather than assumed from the
    // popover's own passing test.
    final PumpedWorkspace pumped = await _openPicker(tester);
    final double rowHeight =
        tester.getCenter(find.text('Author')).dy -
        tester.getCenter(find.text('Refs')).dy;

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(_handle('Refs')),
    );
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 2.5 / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      pumped.container
          .read(graphColumnOrderProvider)
          .map((GbmGraphColumnId id) => id.storageId),
      <String>[
        'graph',
        'message',
        'author',
        'date',
        'hash',
        'refs',
        'committer',
        'changedFiles',
      ],
    );
  });
}
