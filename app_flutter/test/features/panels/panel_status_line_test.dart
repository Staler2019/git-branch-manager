import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/panel_status_line.dart';

/// P19 rule 6 (「狀態列一律寫實際數量與耗時」) composed in one place, so the
/// eleven panels that spell「命中」cannot drift from each other.
///
/// The reason this is a `lib/` function rather than eleven copies is the drift
/// class this whole round exists to close: three panels had already been
/// hand-copied, and eight more were coming. One misspelt 命中 in the eleventh
/// copy is invisible to every test that only ever reads its own panel's string.
void main() {
  group('panelStatusLine', () {
    test('an unfiltered list is just the count, with no 命中 clause', () {
      expect(
        panelStatusLine(
          total: 4,
          shown: 4,
          noun: 'remote',
          nounPlural: 'remotes',
        ),
        '4 remotes',
      );
    });

    test('a filtered list appends 命中 with the count that survived', () {
      expect(
        panelStatusLine(
          total: 4,
          shown: 1,
          noun: 'remote',
          nounPlural: 'remotes',
        ),
        '4 remotes · 命中 1',
      );
    });

    test('one item takes the singular noun', () {
      expect(
        panelStatusLine(
          total: 1,
          shown: 1,
          noun: 'remote',
          nounPlural: 'remotes',
        ),
        '1 remote',
      );
    });

    test('zero items take the plural noun', () {
      expect(
        panelStatusLine(
          total: 0,
          shown: 0,
          noun: 'stash',
          nounPlural: 'stashes',
        ),
        '0 stashes',
      );
    });

    test('nounPlural defaults to noun + s', () {
      expect(
        panelStatusLine(total: 2, shown: 2, noun: 'worktree'),
        '2 worktrees',
      );
    });

    /// The two extra slots differ in *what they describe*, which is why they
    /// are two parameters and not one list: [setFacts] is another fact about
    /// the same set, so it belongs beside the total, while rule 6's 耗時 is
    /// about the measurement rather than the set, so it goes last -- after
    /// 命中, which is still a statement about the set.
    test('setFacts sit beside the total and timing sits last', () {
      expect(
        panelStatusLine(
          total: 4,
          shown: 2,
          noun: 'worktree',
          setFacts: <String>['1 個路徑失效'],
          timing: <String>['掃描 37 ms'],
        ),
        '4 worktrees · 1 個路徑失效 · 命中 2 · 掃描 37 ms',
      );
    });

    test('an empty setFacts or timing adds no separator', () {
      expect(
        panelStatusLine(
          total: 4,
          shown: 4,
          noun: 'worktree',
          setFacts: const <String>[],
          timing: const <String>[],
        ),
        '4 worktrees',
      );
    });
  });
}
