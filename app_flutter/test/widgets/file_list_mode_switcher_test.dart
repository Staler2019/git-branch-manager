import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/widgets/file_list_mode_switcher.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';

import '../support/pump_app.dart';

void main() {
  group('FileListModeSwitcher', () {
    testWidgets('list mode renders every item via leafBuilder in a flat '
        'list', (tester) async {
      await pumpGbmWidget(
        tester,
        child: FileListModeSwitcher<String>(
          mode: FileListViewMode.list,
          items: const <String>['a.dart', 'b/c.dart', 'b/d.dart'],
          pathOf: (String s) => s,
          leafBuilder: (BuildContext context, String s, String label) =>
              Text(label),
        ),
      );

      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
      expect(find.text('b/c.dart'), findsOneWidget);
      expect(find.text('b/d.dart'), findsOneWidget);
      // Flat list mode never groups by folder.
      expect(find.byType(FileTreeFolderRow), findsNothing);
    });

    testWidgets('tree mode groups a multi-file folder under a '
        'FileTreeFolderRow', (tester) async {
      await pumpGbmWidget(
        tester,
        child: FileListModeSwitcher<String>(
          mode: FileListViewMode.tree,
          items: const <String>['a.dart', 'b/c.dart', 'b/d.dart'],
          pathOf: (String s) => s,
          leafBuilder: (BuildContext context, String s, String label) =>
              Text(label),
        ),
      );

      expect(find.byType(FileTreeFolderRow), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      // A root-level file's label is its whole path, because there is no
      // folder row above it to carry a prefix.
      expect(find.text('a.dart'), findsOneWidget);
      // 'b's children are collapsed until the folder row is expanded.
      expect(find.text('c.dart'), findsNothing);
    });

    testWidgets('tree mode expands a folder on tap to reveal its children', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: FileListModeSwitcher<String>(
          mode: FileListViewMode.tree,
          items: const <String>['b/c.dart', 'b/d.dart'],
          pathOf: (String s) => s,
          leafBuilder: (BuildContext context, String s, String label) =>
              Text(label),
        ),
      );

      // This comment used to read "leafBuilder renders the original item
      // string, so a leaf under 'b' still shows its full path ('b/c.dart'),
      // not just the trailing segment" -- an accurate description of the
      // code and a wrong one of the requirement. Spec P03 item 10 makes
      // 「平鋪完整路徑」 the *list* mode's definition and tree mode the
      // folded one; repeating the full path under a folder row that already
      // says the prefix leaves the two modes drawing identical text, which
      // is the switch doing nothing.
      expect(find.text('c.dart'), findsNothing);

      await tester.tap(find.byType(FileTreeFolderRow));
      await tester.pump();

      // The leaf's own segment, under the 'b' row -- not 'b/c.dart'.
      expect(find.text('c.dart'), findsOneWidget);
      expect(find.text('d.dart'), findsOneWidget);
      expect(find.text('b/c.dart'), findsNothing);
    });

    testWidgets('renders emptyBuilder when items is empty', (tester) async {
      await pumpGbmWidget(
        tester,
        child: FileListModeSwitcher<String>(
          mode: FileListViewMode.list,
          items: const <String>[],
          pathOf: (String s) => s,
          leafBuilder: (BuildContext context, String s, String label) =>
              Text(label),
          emptyBuilder: (BuildContext context) => const Text('Nothing here'),
        ),
      );

      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('renders a zero-size box when items is empty and no '
        'emptyBuilder is given', (tester) async {
      await pumpGbmWidget(
        tester,
        child: FileListModeSwitcher<String>(
          mode: FileListViewMode.list,
          items: const <String>[],
          pathOf: (String s) => s,
          leafBuilder: (BuildContext context, String s, String label) =>
              Text(label),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });
  });
}
