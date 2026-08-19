// Unit tests for 05-F's item list as a pure function, mirroring
// `tag_menu_items.dart`/`stash_menu_items.dart`'s own tests. The render site
// (`working_copy_view.dart`'s `_openContextMenu`) is covered by
// `working_copy_view_test.dart`; this file owns the label/order/
// pluralization contract that `context_menu_parity_test.dart` then checks
// against the spec catalog.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_file_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

List<String> _labels(List<GbmMenuItem> items) => items
    .where((GbmMenuItem i) => !i.separator)
    .map((GbmMenuItem i) => i.label)
    .toList();

List<GbmMenuItem> _items({
  int count = 1,
  bool fromStaged = false,
  bool withDiscard = true,
  void Function()? onStageToggle,
  void Function()? onOpenFile,
  void Function()? onShowInFileManager,
  void Function()? onOpenTerminal,
  void Function()? onCopyPath,
  void Function()? onDiscard,
}) {
  return workingCopyFileMenuItems(
    count: count,
    fromStaged: fromStaged,
    onStageToggle: onStageToggle ?? () {},
    onOpenFile: onOpenFile ?? () {},
    onShowInFileManager: onShowInFileManager ?? () {},
    onOpenTerminal: onOpenTerminal ?? () {},
    onCopyPath: onCopyPath ?? () {},
    onDiscard: withDiscard ? (onDiscard ?? () {}) : null,
  );
}

void main() {
  group('spec 05-F order and labels', () {
    test('a single unstaged file gives the six spec items in spec order', () {
      expect(_labels(_items()), <String>[
        'Stage',
        'Open file',
        'Show in file manager',
        'Open terminal here',
        'Copy path',
        'Discard changes…',
      ]);
    });

    test('a staged file swaps Stage for Unstage and drops Discard', () {
      // Discarding restores the work tree from the index, so there is
      // nothing for it to do on the staged side -- the caller passes
      // onDiscard: null there, exactly as the pre-existing menu did.
      expect(_labels(_items(fromStaged: true, withDiscard: false)), <String>[
        'Unstage',
        'Open file',
        'Show in file manager',
        'Open terminal here',
        'Copy path',
      ]);
    });

    test('stays within showGbmContextMenu\'s 8-item cap and danger rules', () {
      final List<GbmMenuItem> items = _items();
      expect(items.last.label, 'Discard changes…');
      expect(items.last.danger, isTrue);
      expect(items[items.length - 2].separator, isTrue);
      expect(() => validateGbmMenuItems(items), returnsNormally);
    });
  });

  group('multi-selection pluralization (spec: "全部動作改為複數並帶數量")', () {
    test('Stage and Discard carry the count', () {
      final List<String> labels = _labels(_items(count: 3));
      expect(labels.first, 'Stage 3 files');
      expect(labels.last, 'Discard changes in 3 files…');
    });

    test('Unstage carries the count too', () {
      expect(
        _labels(_items(count: 3, fromStaged: true, withDiscard: false)).first,
        'Unstage 3 files',
      );
    });

    test(
      'Open file / Show in file manager stay singular -- the spec mock shows '
      'them singular alongside "Stage 3 files", and both act on the '
      'right-clicked row rather than the batch',
      () {
        final List<String> labels = _labels(_items(count: 3));
        expect(labels, contains('Open file'));
        expect(labels, contains('Show in file manager'));
      },
    );
  });

  group('dispatch', () {
    test('each item invokes the callback it was given', () {
      final List<String> fired = <String>[];
      final List<GbmMenuItem> items = _items(
        onStageToggle: () => fired.add('stage'),
        onOpenFile: () => fired.add('open'),
        onShowInFileManager: () => fired.add('reveal'),
        onOpenTerminal: () => fired.add('terminal'),
        onCopyPath: () => fired.add('copy'),
        onDiscard: () => fired.add('discard'),
      );
      for (final GbmMenuItem item in items.where(
        (GbmMenuItem i) => !i.separator,
      )) {
        item.onTap?.call();
      }
      expect(fired, <String>[
        'stage',
        'open',
        'reveal',
        'terminal',
        'copy',
        'discard',
      ]);
    });
  });
}
