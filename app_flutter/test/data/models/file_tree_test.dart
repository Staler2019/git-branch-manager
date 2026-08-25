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

        // Entire path should collapse to single node
        final node = tree.children.firstWhere(
          (node) => node.name.contains('home_screen.dart'),
        );
        expect(node.displayPath, 'lib/app/views/screens/home_screen.dart');
        expect(node.isDirectory, false);
      });
    });

    group('hierarchy and path operations', () {
      test('leaf node reports correct displayPath', () {
        const paths = ['lib/app/views/a.dart'];

        final tree = FileTree.fromPaths(paths);
        final node = tree.children.first;

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

          final FileTreeNode viewsNode = libNode.children.singleWhere(
            (n) => n.displayPath == 'app/views',
          );
          expect(viewsNode.getAllLeafPaths().toSet(), <String>{
            'lib/app/views/home.dart',
            'lib/app/views/settings.dart',
          });

          // lib/models/ collapses into its single leaf child, so it is a file
          // node whose only leaf is itself.
          final FileTreeNode modelsLeaf = libNode.children.singleWhere(
            (n) => n.displayPath == 'lib/models/user.dart',
          );
          expect(modelsLeaf.isDirectory, isFalse);
          expect(modelsLeaf.getAllLeafPaths(), <String>[
            'lib/models/user.dart',
          ]);
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
