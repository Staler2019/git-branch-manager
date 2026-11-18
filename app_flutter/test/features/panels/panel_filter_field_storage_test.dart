// The toolbar's filter field must not share a panel tab's scroll-memory slot
// with the panel's list. A `TextField` scrolls its own text, and its
// Scrollable stores its offset under the nearest `PageStorageKey` chain like
// any other: with no key of its own it took the tab's slot, restored the
// list's offset, clamped it to its own extent and wrote 0 back (P19 rule 1's
// 各自記憶捲動位置; measured with a logging bucket, 2026-11-17).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

Widget _tab({required bool shown, required ScrollController list}) =>
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: shown
            ? KeyedSubtree(
                key: const PageStorageKey<String>('panel-tab-x'),
                child: Column(
                  children: <Widget>[
                    PanelFilterField(query: '', onChanged: (_) {}),
                    Expanded(
                      child: ListView.builder(
                        controller: list,
                        itemCount: 200,
                        itemExtent: 20,
                        itemBuilder: (_, int i) => Text('row $i'),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    );

void main() {
  testWidgets('the list keeps its offset however often the tab returns', (
    tester,
  ) async {
    ScrollController list = ScrollController();
    await tester.pumpWidget(_tab(shown: true, list: list));
    list.jumpTo(380);
    await tester.pumpAndSettle();
    // The offset is stored when a scroll ends, as a drag does.
    await tester.drag(find.byType(ListView), const Offset(0, -1));
    await tester.pumpAndSettle();
    final double scrolled = list.offset;

    for (int visit = 1; visit <= 3; visit++) {
      await tester.pumpWidget(_tab(shown: false, list: list));
      list.dispose();
      list = ScrollController();
      await tester.pumpWidget(_tab(shown: true, list: list));
      await tester.pumpAndSettle();
      expect(list.offset, closeTo(scrolled, 1.0), reason: 'return $visit');
    }
    list.dispose();
  });
}
