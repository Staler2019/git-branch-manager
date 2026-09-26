// `pushDialogRoute` 是全 app 唯一推對話框 route 的路（使用者裁定「全部 26 個對話框都
// 加」）。已量到的事實，這些測試釘的就是它們：
//
// 1. 同一個 dialog route push 兩次會**並存兩個實例**，各自跑一次 initState。對 Prune
//    對話框來說那是兩次 preview 請求；對任何有副作用的對話框都是兩次。
// 2. `currentConfiguration.uri` 停在 base location，**不反映**被 push 的對話框 ——
//    所以防護不能用 `GoRouterState.of(context).uri`。
// 3. `matchedLocation` 丟掉 query string，`ImperativeRouteMatch.matches.uri` 留著 ——
//    所以 `?remote=origin` 與 `?remote=upstream` 必須被視為兩個不同的對話框。
// 4. pop、barrier 點擊、`Navigator.pop` 三條關閉路徑都會清掉那筆 match，這是防護不會
//    永久擋住重開的前提。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:go_router/go_router.dart';

/// Counts how many times each dialog body was built from scratch, which is
/// what a duplicate push actually costs -- a second `initState`, and with it a
/// second copy of whatever that dialog does on open.
class _Mounts {
  final Map<String, int> byLabel = <String, int>{};
  void record(String label) => byLabel[label] = (byLabel[label] ?? 0) + 1;
}

class _Body extends StatefulWidget {
  const _Body({required this.label, required this.mounts});

  final String label;
  final _Mounts mounts;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  void initState() {
    super.initState();
    widget.mounts.record(widget.label);
  }

  @override
  // 小方塊而非填滿的 Text：barrier 那一顆要點得到內容以外的地方。
  Widget build(BuildContext context) => Center(
    child: SizedBox(width: 60, height: 60, child: Text(widget.label)),
  );
}

/// The live stack, in the only form that carries the query string.
List<String> _stack(GoRouter router) => <String>[
  for (final RouteMatchBase m
      in router.routerDelegate.currentConfiguration.matches)
    if (m is ImperativeRouteMatch) m.matches.uri.toString(),
];

void main() {
  late _Mounts mounts;
  late GoRouter router;
  late BuildContext rootContext;

  Future<void> pump(WidgetTester tester) async {
    mounts = _Mounts();
    router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) {
            rootContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
        dialogRoute(
          path: '/first',
          builder: (BuildContext context, GoRouterState state) =>
              _Body(label: 'first', mounts: mounts),
        ),
        dialogRoute(
          path: '/second',
          builder: (BuildContext context, GoRouterState state) =>
              _Body(label: 'second', mounts: mounts),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('第一次推入會開啟對話框', (WidgetTester tester) async {
    await pump(tester);

    pushDialogRoute(rootContext, '/first');
    await tester.pumpAndSettle();

    expect(mounts.byLabel['first'], 1);
    expect(_stack(router), <String>['/first']);
  });

  testWidgets('同一個 URI 第二次推入是 no-op', (WidgetTester tester) async {
    await pump(tester);

    pushDialogRoute(rootContext, '/first');
    await tester.pumpAndSettle();
    pushDialogRoute(rootContext, '/first');
    await tester.pumpAndSettle();

    // 數，不用 any：重複推入的代價正是第二次 initState。
    expect(mounts.byLabel['first'], 1);
    expect(_stack(router), <String>['/first']);
  });

  testWidgets('不同的對話框仍然可以疊上去', (WidgetTester tester) async {
    await pump(tester);

    pushDialogRoute(rootContext, '/first');
    await tester.pumpAndSettle();
    pushDialogRoute(rootContext, '/second');
    await tester.pumpAndSettle();

    expect(mounts.byLabel['first'], 1);
    expect(mounts.byLabel['second'], 1);
    expect(_stack(router), <String>['/first', '/second']);
  });

  testWidgets('query 不同就是不同的對話框，必須都能開', (WidgetTester tester) async {
    // Remotes 面板對 upstream 的 Prune 不該被已開著的 origin 那個擋掉。
    // `matchedLocation` 丟掉 query，所以用它比對會把這兩個當成同一個。
    await pump(tester);

    pushDialogRoute(rootContext, '/first?remote=origin');
    await tester.pumpAndSettle();
    pushDialogRoute(rootContext, '/first?remote=upstream');
    await tester.pumpAndSettle();

    expect(mounts.byLabel['first'], 2);
    expect(_stack(router), <String>[
      '/first?remote=origin',
      '/first?remote=upstream',
    ]);
  });

  testWidgets('帶 query 的同一個 URI 第二次推入也是 no-op', (WidgetTester tester) async {
    // 這一顆才釘住比對基準。上面那顆（query 不同要都能開）在 `matchedLocation` 下也會
    // 綠：`/first` 與 `/first?remote=origin` 本來就不等，閘門根本不觸發，於是兩個都開，
    // 斷言照樣成立。會被弄壞的是**去重**這一半 —— 帶 query 的 URI 在 `matchedLocation`
    // 下永遠等不到自己 ([TEST-fixture-cannot-disagree])。
    await pump(tester);

    pushDialogRoute(rootContext, '/first?remote=origin');
    await tester.pumpAndSettle();
    pushDialogRoute(rootContext, '/first?remote=origin');
    await tester.pumpAndSettle();

    expect(mounts.byLabel['first'], 1);
    expect(_stack(router), <String>['/first?remote=origin']);
  });

  testWidgets('關掉之後可以重開 — 防護不是永久的', (WidgetTester tester) async {
    await pump(tester);

    pushDialogRoute(rootContext, '/first');
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(_stack(router), isEmpty);

    pushDialogRoute(rootContext, '/first');
    await tester.pumpAndSettle();

    expect(mounts.byLabel['first'], 2);
    expect(_stack(router), <String>['/first']);
  });

  testWidgets('barrier 點掉之後也可以重開', (WidgetTester tester) async {
    await pump(tester);

    pushDialogRoute(rootContext, '/first');
    await tester.pumpAndSettle();
    // `dialogRoute` 的 barrierDismissible，點在對話框內容以外的地方。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_stack(router), isEmpty);

    pushDialogRoute(rootContext, '/first');
    await tester.pumpAndSettle();

    expect(mounts.byLabel['first'], 2);
  });
}
