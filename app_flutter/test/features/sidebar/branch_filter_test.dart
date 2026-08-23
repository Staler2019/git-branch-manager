// The sidebar filter's matching rule, as a pure function.
//
// Spec P02-14: 「子字串比對、不分大小寫、斜線視為分隔（打 gl 可命中
// feature/graph-lanes）」. The shipped code was `shortName.toLowerCase()
// .contains(needle)` and nothing else, so **spec's own worked example did
// not match**: `'feature/graph-lanes'.contains('gl')` is false.
//
// Read that example carefully before changing anything here -- it is the
// whole specification of the second rule, and it rules out the obvious
// reading. "Split on `/` and take each segment's initial" gives `feature` ->
// f, `graph-lanes` -> g, i.e. `fg`; the `l` the user typed comes from
// *lanes*, so a word boundary has to include `-` as well. Spec names the
// slash because that is the separator branch names are built from, not as an
// exhaustive list.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/sidebar/branch_filter.dart';

void main() {
  group('the spec example', () {
    test('gl matches feature/graph-lanes', () {
      expect(matchesBranchFilter('feature/graph-lanes', 'gl'), isTrue);
    });
  });

  group('plain substring still wins first', () {
    test('a contiguous run anywhere in the name matches', () {
      expect(matchesBranchFilter('feature/graph-lanes', 'graph'), isTrue);
      expect(matchesBranchFilter('feature/graph-lanes', 'ph-la'), isTrue);
      expect(matchesBranchFilter('release/1.2.3', '1.2'), isTrue);
    });

    test('a query containing the separator matches literally', () {
      expect(matchesBranchFilter('feature/graph-lanes', 'e/g'), isTrue);
    });

    test('matching ignores case on both sides', () {
      expect(matchesBranchFilter('Feature/Graph-Lanes', 'graph'), isTrue);
      expect(matchesBranchFilter('feature/graph-lanes', 'GRAPH'), isTrue);
      expect(matchesBranchFilter('Feature/Graph-Lanes', 'GL'), isTrue);
    });
  });

  group('initials', () {
    test('a run of consecutive word initials matches', () {
      expect(matchesBranchFilter('feature/graph-lanes', 'fg'), isTrue);
      expect(matchesBranchFilter('feature/graph-lanes', 'fgl'), isTrue);
      expect(matchesBranchFilter('feature/graph-lanes', 'f'), isTrue);
    });

    test('underscore and dot are word boundaries too', () {
      expect(matchesBranchFilter('feature/my_new_thing', 'nt'), isTrue);
      expect(matchesBranchFilter('release/v1.beta.two', 'bt'), isTrue);
    });

    test('a lower-to-upper transition is a word boundary', () {
      expect(matchesBranchFilter('feature/graphLanes', 'gl'), isTrue);
    });

    test('initials must be consecutive, not merely in order', () {
      // The rule chosen is **substring over the initials**, not subsequence.
      // Both satisfy spec's single example; substring is the narrower one,
      // and this repo does not widen past the spec on its own initiative.
      // `f`(eature) `g`(raph) `l`(anes) -> "fgl", so `fl` is in order but not
      // consecutive.
      //
      // If a future spec revision does ask for fuzzy matching, this is the
      // test that says the current behaviour was a decision: switch
      // `_initialsOf(...).contains(q)` to a subsequence walk and flip this
      // one case.
      expect(matchesBranchFilter('feature/graph-lanes', 'fl'), isFalse);
    });
  });

  group('non-matches', () {
    test('a name sharing no run and no initials does not match', () {
      expect(matchesBranchFilter('feature/graph-lanes', 'xyz'), isFalse);
      expect(matchesBranchFilter('main', 'gl'), isFalse);
    });

    test('a query longer than the name cannot match', () {
      expect(matchesBranchFilter('main', 'mainline'), isFalse);
    });
  });

  group('an empty query filters nothing out', () {
    test('empty and whitespace-only both match everything', () {
      expect(matchesBranchFilter('feature/graph-lanes', ''), isTrue);
      expect(matchesBranchFilter('feature/graph-lanes', '   '), isTrue);
      expect(matchesBranchFilter('', ''), isTrue);
    });

    test('a non-empty query never matches an empty name', () {
      expect(matchesBranchFilter('', 'a'), isFalse);
    });
  });
}
