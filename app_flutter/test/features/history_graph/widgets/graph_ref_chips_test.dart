import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_ref_chips.dart';

RefInfo _ref(String name, String target, {RefKind kind = RefKind.localBranch}) {
  return RefInfo(
    fullName: 'refs/heads/$name',
    shortName: name,
    kind: kind,
    target: target,
    upstream: '',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: false,
    isGone: false,
    isHead: false,
    isSymbolic: false,
    worktreePath: '',
  );
}

void main() {
  group('refChipsForCommit', () {
    test('returns an empty list when no ref points to the commit', () {
      const refs = RefSnapshot.empty;

      expect(refChipsForCommit(refs, 'deadbeef'), isEmpty);
    });

    test('returns the single ref pointing to the commit', () {
      final RefInfo main = _ref('main', 'abc123');
      final refs = RefSnapshot(
        head: RefSnapshot.empty.head,
        refs: <RefInfo>[main],
        refCountGuardTripped: false,
        totalRefCount: 1,
      );

      final result = refChipsForCommit(refs, 'abc123');

      expect(result, hasLength(1));
      expect(result.single.shortName, 'main');
    });

    test('returns every ref pointing to the same commit', () {
      final RefInfo main = _ref('main', 'abc123');
      final RefInfo tag = _ref('v1.0', 'abc123', kind: RefKind.tag);
      final RefInfo other = _ref('other', 'def456');
      final refs = RefSnapshot(
        head: RefSnapshot.empty.head,
        refs: <RefInfo>[main, tag, other],
        refCountGuardTripped: false,
        totalRefCount: 3,
      );

      final result = refChipsForCommit(refs, 'abc123');

      expect(result, hasLength(2));
      expect(
        result.map((r) => r.shortName),
        containsAll(<String>['main', 'v1.0']),
      );
      expect(result.map((r) => r.shortName), isNot(contains('other')));
    });
  });
}
