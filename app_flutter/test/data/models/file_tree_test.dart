import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/file_tree.dart';

void main() {
  group('FileTree', () {
    group('build from flat paths', () {
      test('builds tree from flat file paths', () {
        const paths = [
          'lib/app/views/a.dart',
          'lib/app/views/b.dart',
          'README.md',
        ];

        final tree = FileTree.fromPaths(paths);
        expect(tree.children, isNotEmpty);
      });

      test('empty list returns empty tree', () {
        final tree = FileTree.fromPaths([]);
        expect(tree.children, isEmpty);
      });

      test('single file at root level', () {
        const paths = ['README.md'];

        final tree = FileTree.fromPaths(paths);
        expect(tree.children, hasLength(1));
        expect(tree.children[0].name, 'README.md');
        expect(tree.children[0].isDirectory, false);
      });

      test('multiple files at root level', () {
        const paths = ['README.md', 'LICENSE', 'pubspec.yaml'];

        final tree = FileTree.fromPaths(paths);
        expect(tree.children, hasLength(3));
      });

      test('nested structure with multiple levels', () {
        const paths = [
          'lib/app/views/home.dart',
          'lib/app/models/user.dart',
          'lib/utils/helpers.dart',
        ];

        final tree = FileTree.fromPaths(paths);

        // Should have 'lib' directory as child
        final libNode = tree.children.firstWhere(
          (node) => node.name == 'lib',
          orElse: () => throw 'lib directory not found',
        );
        expect(libNode.isDirectory, true);
      });
    });

    group('single child collapsing', () {
      test('collapses single-child folders into one display path', () {
        const paths = ['lib/app/views/a.dart', 'lib/app/views/b.dart'];

        final tree = FileTree.fromPaths(paths);

        // lib -> app -> views has one child path (views), so it should be
        // collapsed to "lib/app/views" single display node
        final libNode = tree.children.firstWhere(
          (node) => node.name.startsWith('lib'),
        );

        // The collapsed path should include all single-child folders
        expect(libNode.name, contains('views'));
      });

      test('does not collapse if folder has multiple children at any level', () {
        const paths = ['lib/app/views/a.dart', 'lib/app/models/user.dart'];

        final tree = FileTree.fromPaths(paths);

        // lib -> app collapses into lib/app (both single children)
        // but app has multiple children (views, models), so lib/app stops there
        final libNode = tree.children.firstWhere(
          (node) => node.name.startsWith('lib'),
        );
        expect(libNode.name, equals('lib/app'));
        expect(libNode.children, hasLength(2)); // views and models
      });

      test('file at root is not collapsed', () {
        const paths = ['README.md'];

        final tree = FileTree.fromPaths(paths);
        expect(tree.children[0].name, equals('README.md'));
        expect(tree.children[0].isDirectory, false);
      });

      test('single file in deeply nested single-child folders', () {
        const paths = ['lib/app/views/screens/home_screen.dart'];

        final tree = FileTree.fromPaths(paths);

        // The *folder* chain collapses all the way -- that half is spec P03
        // item 10's own 「只有一個子項的資料夾會自動串接成 lib/app/views 一
        // 列」 -- and then stops, leaving the file as an ordinary child row.
        //
        // ~~This used to assert the whole chain ended up in the file's own
        // `name`~~, which is what 使用者裁定（2026-09-05）overturned:
        // 「folder 可以堆疊名稱，但是檔案不會有 folder」. Corrected in place
        // rather than deleted, because the premise is what changed.
        final FileTreeNode folder = tree.children.single;
        expect(folder.isDirectory, isTrue);
        expect(folder.name, 'lib/app/views/screens');

        final FileTreeNode file = folder.children.single;
        expect(file.isDirectory, isFalse);
        expect(file.name, 'home_screen.dart');
        expect(file.displayPath, 'lib/app/views/screens/home_screen.dart');
      });

      // ~~'a folder holding one file collapses into it, prefix and all'~~ --
      // the same assertion, inverted by 使用者裁定（2026-09-05）. A folder
      // holding exactly one file keeps its own row; only folder-to-folder
      // chains stack.
      test('a folder holding one file keeps its own row', () {
        final tree = FileTree.fromPaths(const <String>['b/c.dart']);

        final FileTreeNode folder = tree.children.single;
        expect(folder.isDirectory, isTrue);
        expect(folder.name, 'b');

        final FileTreeNode file = folder.children.single;
        expect(file.isDirectory, isFalse);
        expect(file.name, 'c.dart');
        expect(file.displayPath, 'b/c.dart');
      });

      // 使用者裁定（2026-09-05）:「樹狀模式下，我想要的是像 vscode 一樣，
      // folder 可以堆疊名稱，但是檔案不會有 folder」, reported against this
      // exact shape -- `docs` drew two rows reading
      // `ledger/<file>.md` and `rules/<file>.md`, with no folder row at all.
      test(
        'a folder whose single child is a file is not compacted into it',
        () {
          final tree = FileTree.fromPaths(const <String>[
            'docs/ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md',
            'docs/rules/fn-flutter-layout.md',
          ]);

          final FileTreeNode docs = tree.children.single;
          expect(docs.name, 'docs');
          expect(docs.isDirectory, isTrue);
          expect(docs.children.map((FileTreeNode n) => n.name), <String>[
            'ledger',
            'rules',
          ]);
          expect(docs.children.map((FileTreeNode n) => n.isDirectory), <bool>[
            true,
            true,
          ]);

          final FileTreeNode ledgerFile = docs.children.first.children.single;
          expect(ledgerFile.isDirectory, isFalse);
          expect(
            ledgerFile.name,
            '2026-09-05-feat-worktree-dialogs-shell-redesign.md',
          );
          expect(
            ledgerFile.displayPath,
            'docs/ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md',
          );
        },
      );
    });

    group('hierarchy and path operations', () {
      test('leaf node reports correct displayPath', () {
        const paths = ['lib/app/views/a.dart'];

        final tree = FileTree.fromPaths(paths);
        // The chain collapses down to the folder and stops there, so the leaf
        // is that folder's child rather than the tree's own -- 使用者裁定
        // （2026-09-05）. Its `displayPath` is still the full path.
        final node = tree.children.first.children.single;

        expect(node.displayPath, 'lib/app/views/a.dart');
      });

      test('directory node reports correct displayPath', () {
        const paths = ['lib/a.dart', 'lib/b.dart'];

        final tree = FileTree.fromPaths(paths);
        final libNode = tree.children.first;

        expect(libNode.displayPath, 'lib');
      });

      test('node knows if it is directory', () {
        const paths = ['lib/app/a.dart', 'lib/app/b.dart', 'README.md'];

        final tree = FileTree.fromPaths(paths);

        final libNode = tree.children.firstWhere(
          (node) => node.displayPath.startsWith('lib'),
        );
        final readmeNode = tree.children.firstWhere(
          (node) => node.displayPath == 'README.md',
        );

        expect(libNode.isDirectory, true);
        expect(readmeNode.isDirectory, false);
      });

      test('children are computed correctly for directory', () {
        const paths = ['lib/a.dart', 'lib/b.dart'];

        final tree = FileTree.fromPaths(paths);

        final libNode = tree.children.first;
        expect(libNode.children, isNotEmpty);
        expect(libNode.children.length, 2);
      });

      test('leaf node has no children', () {
        const paths = ['README.md'];

        final tree = FileTree.fromPaths(paths);

        final readmeNode = tree.children.first;
        expect(readmeNode.children, isEmpty);
      });
    });

    group('all leaf paths', () {
      test('returns all file paths for tree with files only', () {
        const paths = ['README.md', 'LICENSE', 'pubspec.yaml'];

        final tree = FileTree.fromPaths(paths);
        final leaves = tree.getAllLeafPaths();

        expect(leaves, unorderedEquals(paths));
      });

      test('returns all file paths for tree with nested structure', () {
        const paths = [
          'lib/app/views/a.dart',
          'lib/app/views/b.dart',
          'README.md',
        ];

        final tree = FileTree.fromPaths(paths);
        final leaves = tree.getAllLeafPaths();

        expect(leaves, unorderedEquals(paths));
      });

      test('returns empty list for tree with no files', () {
        final tree = FileTree.fromPaths([]);
        final leaves = tree.getAllLeafPaths();

        expect(leaves, isEmpty);
      });

      test('directory node returns only its leaf descendants', () {
        const paths = ['lib/a.dart', 'lib/b.dart', 'src/c.dart'];

        final tree = FileTree.fromPaths(paths);
        final libNode = tree.children.firstWhere(
          (node) => node.displayPath == 'lib',
        );

        final leaves = libNode.getAllLeafPaths();

        expect(leaves, unorderedEquals(['lib/a.dart', 'lib/b.dart']));
      });
    });

    group('complete workflow', () {
      test('correctly builds tree with mixed single and multi-child paths', () {
        const allPaths = [
          'lib/app/views/home.dart',
          'lib/app/views/settings.dart',
          'lib/models/user.dart',
        ];

        final tree = FileTree.fromPaths(allPaths);

        // Should have lib node
        expect(tree.children, isNotEmpty);
        expect(
          tree.children.where((n) => n.name.startsWith('lib')).length,
          greaterThan(0),
        );
      });

      // Was a tri-state getCheckState test until that method was deleted with
      // the board's checkboxes. The structural claims it made are the part
      // worth keeping -- which node is a folder, which one collapsed into a
      // leaf, and what sits under each -- so they are asserted through
      // getAllLeafPaths(), the one accessor the folder drag still uses.
      test(
        'a partly-collapsed tree reports the right leaves at every level',
        () {
          const allPaths = [
            'lib/app/views/home.dart',
            'lib/app/views/settings.dart',
            'lib/models/user.dart',
            'README.md',
          ];

          final tree = FileTree.fromPaths(allPaths);

          expect(tree.getAllLeafPaths().toSet(), allPaths.toSet());

          final FileTreeNode libNode = tree.children.singleWhere(
            (n) => n.name == 'lib',
          );
          expect(libNode.getAllLeafPaths().toSet(), <String>{
            'lib/app/views/home.dart',
            'lib/app/views/settings.dart',
            'lib/models/user.dart',
          });

          // Root-anchored: this row draws 「app/views」 (its `name`) but is
          // keyed 'lib/app/views', so it cannot share an expand/collapse key
          // with an `app/views` under some other parent.
          final FileTreeNode viewsNode = libNode.children.singleWhere(
            (n) => n.displayPath == 'lib/app/views',
          );
          expect(viewsNode.name, 'app/views');
          expect(viewsNode.getAllLeafPaths().toSet(), <String>{
            'lib/app/views/home.dart',
            'lib/app/views/settings.dart',
          });

          // ~~lib/models/ collapses into its single leaf child~~ -- it keeps
          // its own folder row now (使用者裁定, 2026-09-05), holding one file.
          final FileTreeNode modelsNode = libNode.children.singleWhere(
            (n) => n.name == 'models',
          );
          expect(modelsNode.isDirectory, isTrue);
          expect(modelsNode.getAllLeafPaths(), <String>[
            'lib/models/user.dart',
          ]);
          expect(modelsNode.children.single.name, 'user.dart');
        },
      );

      test('collapses a full single-child chain (lib -> app -> views) into '
          'one top-level display path, matching the spec p.03 example', () {
        const paths = ['lib/app/views/a.dart', 'lib/app/views/b.dart'];

        final tree = FileTree.fromPaths(paths);

        // lib has exactly one child (app), which has exactly one child
        // (views), which has two children (a.dart, b.dart) -- so the chain
        // collapses all the way down to a single top-level row.
        expect(tree.children, hasLength(1));
        final FileTreeNode collapsed = tree.children.single;
        expect(collapsed.displayPath, 'lib/app/views');
        expect(collapsed.isDirectory, true);
        expect(
          collapsed.children.map((n) => n.displayPath),
          unorderedEquals(<String>[
            'lib/app/views/a.dart',
            'lib/app/views/b.dart',
          ]),
        );

        // List mode (flat): unaffected by collapsing, still 2 individual leaves.
        final flatPaths = tree.getAllLeafPaths();
        expect(flatPaths, unorderedEquals(paths));
      });
    });
  });
}
