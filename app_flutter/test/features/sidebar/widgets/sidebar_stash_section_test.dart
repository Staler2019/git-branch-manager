// Covers the three gaps reported against the sidebar's STASH section:
// no hover/selected feedback (the row was a hand-rolled GestureDetector +
// Container, never migrated onto GbmRow -- [FLU-hand-rolled-inkwell-hover]),
// no discoverable "more actions" affordance to match BranchTreeItem's ⋯
// button, and a relative-date bug ("20676d ago") from feeding unix
// *seconds* into DateTime.fromMillisecondsSinceEpoch with no `* 1000`.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/stash_entry.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_date_format.dart';
import 'package:gbm_flutter/features/sidebar/widgets/sidebar_stash_section.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';

import '../../../support/fake_repo_session.dart';
import '../../../support/pump_app.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

const StashEntry _stash0 = StashEntry(
  index: 0,
  message: 'WIP on main: tab row',
  oid: 'aaaaaaa',
  timestamp: 1700000000,
);

const StashEntry _stash1 = StashEntry(
  index: 1,
  message: 'debug logging',
  oid: 'bbbbbbb',
  timestamp: 1690000000,
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  List<StashEntry> stashes = const <StashEntry>[_stash0, _stash1],
}) async {
  late final FakeRepoSessionController fake;
  await pumpGbmWidget(
    tester,
    child: SidebarStashSection(identity: _identity, stashes: stashes),
    overrides: <Override>[
      repoSessionProvider(_identity).overrideWith((ref) {
        fake = FakeRepoSessionController(
          _identity,
          RepoSessionState(isOpen: true, stashes: stashes),
        );
        return fake;
      }),
    ],
  );
  return fake;
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(finder));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('SidebarStashSection rows', () {
    testWidgets('each row is a GbmRow (hover) and selecting flips its token', (
      tester,
    ) async {
      await _pump(tester);

      // GbmRow is what supplies hoverColor/surfaceSelected -- the previous
      // implementation was a bare GestureDetector+Container with neither.
      expect(find.byType(GbmRow), findsNWidgets(2));

      GbmRow rowFor(String message) => tester.widget<GbmRow>(
        find.ancestor(of: find.text(message), matching: find.byType(GbmRow)),
      );

      expect(rowFor(_stash0.message).selected, isFalse);
      expect(rowFor(_stash1.message).selected, isFalse);

      await tester.tap(find.text(_stash0.message));
      await tester.pumpAndSettle();

      expect(rowFor(_stash0.message).selected, isTrue);
      expect(rowFor(_stash1.message).selected, isFalse);

      // Selecting the other row moves the highlight rather than adding to it.
      await tester.tap(find.text(_stash1.message));
      await tester.pumpAndSettle();

      expect(rowFor(_stash0.message).selected, isFalse);
      expect(rowFor(_stash1.message).selected, isTrue);
    });

    testWidgets('the ⋯ button and right-click both open the same 05-H menu', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        stashes: const <StashEntry>[_stash0],
      );

      // Undiscoverable-but-real right-click path.
      await _rightClick(tester, find.text(_stash0.message));
      expect(find.text('Apply stash'), findsOneWidget);
      await tester.tap(find.text('Apply stash'));
      await tester.pumpAndSettle();

      expect(
        fake.commandLog.where((FakeCommand c) => c.name == 'applyStash'),
        hasLength(1),
      );

      // The new discoverable path: the trailing ⋯ button, mirroring
      // BranchTreeItem's.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Drop stash…'), findsOneWidget);
      await tester.tap(find.text('Drop stash…'));
      await tester.pumpAndSettle();

      expect(
        fake.commandLog.where((FakeCommand c) => c.name == 'dropStash'),
        hasLength(1),
      );
    });

    testWidgets(
      'renders the correct date -- regression for the 1000x "20676d ago" bug',
      (tester) async {
        // A fixed instant well in the past. If the bug (feeding *seconds*
        // straight into fromMillisecondsSinceEpoch) ever comes back, this
        // would render a date in January 1970 instead.
        final DateTime past = DateTime.now().subtract(const Duration(days: 10));
        final int timestampSeconds = past.millisecondsSinceEpoch ~/ 1000;
        final StashEntry stash = StashEntry(
          index: 0,
          message: 'WIP on main: date check',
          oid: 'ccccccc',
          timestamp: timestampSeconds,
        );

        await _pump(tester, stashes: <StashEntry>[stash]);

        final String expected = formatGraphDate(
          DateTime.fromMillisecondsSinceEpoch(timestampSeconds * 1000),
          DateTime.now(),
        );

        expect(find.text(expected), findsOneWidget);
        expect(find.textContaining('1970'), findsNothing);
      },
    );
  });
}
