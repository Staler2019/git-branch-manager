// CompareTabsNotifier is pure in-memory UI state (which Compare tabs are
// open, and each one's left/right/threeDot selection) -- not FFI-backed, so
// this drives the notifier class directly, the same way
// FileListViewModeNotifier's tests would if it had a bare in-memory mode.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';

void main() {
  group('CompareTabSpec', () {
    test('rightIsWorkingCopy is true when right is null', () {
      const CompareTabSpec spec = CompareTabSpec(id: 't1', left: 'main');
      expect(spec.rightIsWorkingCopy, isTrue);
    });

    test('rightIsWorkingCopy is false when right is a ref', () {
      const CompareTabSpec spec = CompareTabSpec(
        id: 't1',
        left: 'main',
        right: 'feature',
      );
      expect(spec.rightIsWorkingCopy, isFalse);
    });
  });

  group('CompareTabsNotifier', () {
    test('starts with no open tabs', () {
      final CompareTabsNotifier notifier = CompareTabsNotifier();
      expect(notifier.state, isEmpty);
    });

    test('open() appends a new tab and returns its id', () {
      final CompareTabsNotifier notifier = CompareTabsNotifier();

      final String id = notifier.open(left: 'main');

      expect(notifier.state, hasLength(1));
      expect(notifier.state.single.id, id);
      expect(notifier.state.single.left, 'main');
      expect(notifier.state.single.rightIsWorkingCopy, isTrue);
    });

    test('open() assigns distinct ids to successive tabs', () {
      final CompareTabsNotifier notifier = CompareTabsNotifier();

      final String first = notifier.open(left: 'main');
      final String second = notifier.open(left: 'develop', right: 'main');

      expect(first, isNot(second));
      expect(notifier.state, hasLength(2));
    });

    test('close() removes exactly the tab with the given id', () {
      final CompareTabsNotifier notifier = CompareTabsNotifier();
      final String keep = notifier.open(left: 'main');
      final String drop = notifier.open(left: 'develop');

      notifier.close(drop);

      expect(notifier.state, hasLength(1));
      expect(notifier.state.single.id, keep);
    });

    test('close() with an unknown id is a no-op', () {
      final CompareTabsNotifier notifier = CompareTabsNotifier();
      notifier.open(left: 'main');

      notifier.close('does-not-exist');

      expect(notifier.state, hasLength(1));
    });

    test('updateRefs() replaces left/right/threeDot for the matching tab '
        'only', () {
      final CompareTabsNotifier notifier = CompareTabsNotifier();
      final String target = notifier.open(left: 'main');
      final String other = notifier.open(left: 'develop');

      notifier.updateRefs(
        target,
        left: 'main',
        right: 'feature',
        threeDot: false,
      );

      final CompareTabSpec updated = notifier.state.firstWhere(
        (t) => t.id == target,
      );
      expect(updated.right, 'feature');
      expect(updated.threeDot, isFalse);
      final CompareTabSpec untouched = notifier.state.firstWhere(
        (t) => t.id == other,
      );
      expect(untouched.left, 'develop');
      expect(untouched.rightIsWorkingCopy, isTrue);
    });

    test(
      'updateScrollOffset() stores the offset for the matching tab only',
      () {
        final CompareTabsNotifier notifier = CompareTabsNotifier();
        final String target = notifier.open(left: 'main');

        notifier.updateScrollOffset(target, 240.5);

        expect(
          notifier.state.firstWhere((t) => t.id == target).scrollOffset,
          240.5,
        );
      },
    );
  });
}
