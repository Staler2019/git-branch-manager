import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_scroll_controller.dart';

/// A zero-height marker that registers itself as [segment]'s spacer.
class _Spacer extends StatefulWidget {
  const _Spacer(this.sync, this.column, this.segment);

  final SyncScrollController sync;
  final int column;
  final int segment;

  @override
  State<_Spacer> createState() => _SpacerState();
}

class _SpacerState extends State<_Spacer> {
  @override
  void initState() {
    super.initState();
    widget.sync.registerSpacer(widget.column, widget.segment, context);
  }

  @override
  void dispose() {
    widget.sync.unregisterSpacer(widget.column, widget.segment, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 0);
}

void main() {
  testWidgets('the follower is corrected against the spacer nearest the '
      "leader's top, not any other one both have built", (tester) async {
    // Segment k ends at the sum of the first k+1 item heights. Column 1's
    // item 2 is 50 taller and its item 3 50 shorter, so the two columns
    // agree at every spacer except segment 2's -- as they do for a frame
    // while one column's measured height has not reached the slot heights
    // yet. At the leader's top (600) segment 2's spacer is the one being
    // read; segments 1 and 3, also built, say there is no drift.
    const List<List<double>> items = <List<double>>[
      <double>[200, 200, 200, 200, 200, 200, 200, 200],
      <double>[200, 200, 250, 150, 200, 200, 200, 200],
    ];
    final List<ScrollController> columns = <ScrollController>[
      ScrollController(),
      ScrollController(),
    ];
    final SyncScrollController sync = SyncScrollController(columns);
    addTearDown(() {
      sync.dispose();
      for (final ScrollController c in columns) {
        c.dispose();
      }
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            for (int c = 0; c < 2; c++)
              SizedBox(
                width: 200,
                height: 300,
                child: ListView(
                  controller: columns[c],
                  children: <Widget>[
                    for (int k = 0; k < items[c].length; k++) ...<Widget>[
                      SizedBox(height: items[c][k]),
                      _Spacer(sync, c, k),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(sync.leader, 0);

    columns[0].jumpTo(600);
    await tester.pump();
    await tester.pump();

    expect(columns[1].offset, 650);
  });
}
