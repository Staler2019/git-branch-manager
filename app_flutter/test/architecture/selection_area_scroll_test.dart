// Flutter's own selection autoscroll (`EdgeDraggingAutoScroller._scroll`)
// awaits itself once per step, so a selection drag held past a vertical
// scrollable's edge overflows the stack on release (measured in
// `lib/widgets/selection_edge_scroll.dart`). `GbmCodeHScroll` wraps its child
// in `SelectionEdgeScroll`, which takes that autoscroll over; a selectable
// surface built without it gets the framework's back. This pins the pairing
// by reading the source, as `data_layer_imports_test.dart` does for imports.
// `SelectableText` is not covered: it is an `EditableText`, and never reaches
// that autoscroller.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _selectable = RegExp(r'\b(?:SelectionArea|SelectableRegion)\(');

void main() {
  test('每個 SelectionArea 都經過 GbmCodeHScroll', () {
    final List<String> scanned = <String>[];
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.readAsStringSync();
      if (!_selectable.hasMatch(source)) continue;
      scanned.add(entity.path);
      if (!source.contains('GbmCodeHScroll(')) offenders.add(entity.path);
    }

    // Four today (diff page, scoped diff, side-by-side, panel text); an empty
    // scan would pass for the wrong reason.
    expect(scanned, hasLength(greaterThanOrEqualTo(4)));
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
