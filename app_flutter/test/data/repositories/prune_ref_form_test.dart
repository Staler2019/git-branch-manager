import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/remote_prune_preview_entry.dart';

void main() {
  group('pruneRefArguments', () {
    test('a full ref name is reduced to the short form git accepts', () {
      // Measured against real git 2.55.0 in a scratch repository:
      //
      //   $ git branch --delete --remotes refs/remotes/origin/feat/x
      //   error: remote-tracking branch 'refs/remotes/origin/feat/x' not found
      //   exit=1
      //   $ git branch --delete --remotes origin/feat/x
      //   Deleted remote-tracking branch origin/feat/x (was 668c5ce).
      //   exit=0
      //
      // `git branch -r -d` resolves its argument relative to refs/remotes/,
      // so a full name asks for refs/remotes/refs/remotes/origin/feat/x.
      expect(
        pruneRefArguments(<String>['refs/remotes/origin/feat/x']),
        <String>['origin/feat/x'],
      );
    });

    test('a short name is passed through unchanged', () {
      // The Prune dialog sends git's own short names; normalising must not
      // mangle the form that already worked.
      expect(pruneRefArguments(<String>['origin/feat/x']), <String>[
        'origin/feat/x',
      ]);
    });

    test('a mixed list is normalised entry by entry', () {
      // The two producers disagreed on form for months (see this function's
      // doc comment), so a list carrying both is the realistic input.
      expect(
        pruneRefArguments(<String>[
          'refs/remotes/origin/a',
          'upstream/b',
          'refs/remotes/origin/feature/nested/c',
        ]),
        <String>['origin/a', 'upstream/b', 'origin/feature/nested/c'],
      );
    });

    test('a branch name containing "refs/remotes/" mid-path is not '
        'truncated twice', () {
      // shortRemoteRefName strips only a *leading* prefix. A branch really
      // named `origin/wip/refs/remotes/x` must survive one pass and stay
      // stable on a second -- the idempotence the two producers rely on.
      const String once = 'origin/wip/refs/remotes/x';
      expect(pruneRefArguments(<String>[once]), <String>[once]);
      expect(pruneRefArguments(pruneRefArguments(<String>[once])), <String>[
        once,
      ]);
    });

    test('an empty list stays empty', () {
      expect(pruneRefArguments(const <String>[]), isEmpty);
    });
  });
}
