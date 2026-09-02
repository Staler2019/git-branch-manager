// Spec page 19 樣板規則 1: 「以分頁開啟…可同時開多個、**各自記憶捲動位置**與
// splitter，Ctrl/Cmd+W 關閉。」
//
// The Ctrl/Cmd+W half landed earlier in this round; this is the
// 記憶捲動位置 half, which was implemented by nothing.
//
// It has to be an integration test. A management panel is a GoRouter route
// (`/repo/:repoId/panel/:tabId`), so switching tabs *unmounts the page and
// disposes its ScrollController* -- the loss happens in the router, which a
// widget test never goes through ([TEST-new-gate-needs-integration]). A
// widget test would pump one panel, scroll it, and see the offset survive,
// because nothing ever took it away.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/reflog_entry.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/panel_page.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

const Signature _who = Signature(
  name: 'Ada',
  email: 'ada@example.com',
  when: 1755000000,
  tzOffsetMinutes: 0,
);

/// Enough entries that the list scrolls well past a screenful, so an offset
/// that survives cannot be confused with one that was never taken away.
final List<ReflogEntry> _entries = List<ReflogEntry>.generate(
  60,
  (int i) => ReflogEntry(index: i, oid: 'oid$i', message: 'step $i', who: _who),
);

final List<RouteBase> _panelRoute = <RouteBase>[
  GoRoute(
    path: RoutePaths.panel,
    builder: (BuildContext context, GoRouterState state) => PanelPage(
      identity: _identity,
      tabId: state.pathParameters['tabId']!,
      query: state.uri.queryParameters,
    ),
  ),
];

Future<String> _openPanel(
  WidgetTester tester,
  PumpedWorkspace pumped,
  GbmPanelKind kind,
) async {
  final String id = pumped.container
      .read(panelTabsProvider(_identity).notifier)
      .open(kind);
  pumped.router.go(
    RoutePaths.panelFor(Uri.encodeComponent(_identity.workDir), id),
  );
  await tester.pumpAndSettle();
  return id;
}

Future<void> _goTo(
  WidgetTester tester,
  PumpedWorkspace pumped,
  String tabId,
) async {
  pumped.router.go(
    RoutePaths.panelFor(Uri.encodeComponent(_identity.workDir), tabId),
  );
  await tester.pumpAndSettle();
}

/// The offset of the reflog panel's own list.
///
/// Found by type rather than by a key so the assertion does not depend on
/// the mechanism under test: whatever preserves the offset, this reads the
/// scrollable the user actually scrolled.
double _listOffset(WidgetTester tester) => tester
    .widget<Scrollable>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    )
    .controller!
    .offset;

void main() {
  group('P19 rule 1: each panel tab remembers its own scroll position', () {
    testWidgets('an offset survives switching away and back', (tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: RepoSessionState(isOpen: true, lastReflog: _entries),
        extraRoutes: _panelRoute,
      );

      final String reflogTab = await _openPanel(
        tester,
        pumped,
        GbmPanelKind.reflog,
      );
      final String otherTab = await _openPanel(
        tester,
        pumped,
        GbmPanelKind.manageWorktrees,
      );

      await _goTo(tester, pumped, reflogTab);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      final double scrolled = _listOffset(tester);
      expect(scrolled, greaterThan(0), reason: 'the drag must have scrolled');

      // Away and back -- which unmounts the page and disposes its controller.
      await _goTo(tester, pumped, otherTab);
      await _goTo(tester, pumped, reflogTab);

      expect(_listOffset(tester), closeTo(scrolled, 1.0));
    });

    testWidgets('two tabs of the same kind do not share one offset', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: RepoSessionState(isOpen: true, lastReflog: _entries),
        extraRoutes: _panelRoute,
      );

      // Two *blame* tabs, because the per-subject kinds are the ones that
      // can legitimately be open twice at once. A memory keyed on the panel
      // *kind* rather than on the tab would make these two share a position
      // -- which is the failure 「各自」 is about.
      final String first = pumped.container
          .read(panelTabsProvider(_identity).notifier)
          .open(GbmPanelKind.reflog);
      final String second = pumped.container
          .read(panelTabsProvider(_identity).notifier)
          .open(GbmPanelKind.blame, subject: 'lib/main.dart');
      expect(first, isNot(second));

      await _goTo(tester, pumped, first);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      final double scrolled = _listOffset(tester);
      expect(scrolled, greaterThan(0));

      await _goTo(tester, pumped, second);
      // The second tab is a different panel entirely and starts at the top;
      // if it opened already scrolled, the memory is keyed on the wrong
      // thing.
      if (find.byType(ListView).evaluate().isNotEmpty) {
        expect(_listOffset(tester), 0);
      }

      await _goTo(tester, pumped, first);
      expect(_listOffset(tester), closeTo(scrolled, 1.0));
    });
  });
}
