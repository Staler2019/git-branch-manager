// `pushDialogRoute` 只在**每一個**呼叫點都走它的時候才是防護。這一顆用原始碼斷言那件事。
//
// 為什麼要有：前一輪把 48 個呼叫點從 `context.push(RoutePaths.…Dialog…)` 改過去，沒有任何
// 編譯器或型別能阻止第 49 個又寫回原本的形狀 —— 那個呼叫點會靜靜地繞過去，而症狀（同一個
// 對話框開兩個）只在使用者連點時出現。以字串斷言原始碼在這個 repo 有先例
// （`test/platform/window_title_test.dart` 就是這樣釘 runner 原始碼的）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 單行與多行都要涵蓋：`\s*` 在 `dotAll` 下會跨行，而實際有 20 個呼叫點是被
/// `dart format` 拆成多行的。`.push<void>(…)` 這種帶型別參數的形式也要吃到。
final RegExp _bareDialogPush = RegExp(
  r'\.push(?:<[^>]*>)?\(\s*RoutePaths\.[A-Za-z0-9_]*[Dd]ialog',
  dotAll: true,
);

void main() {
  test('lib/ 底下沒有任何對話框 route 繞過 pushDialogRoute', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.readAsStringSync();
      for (final RegExpMatch match in _bareDialogPush.allMatches(source)) {
        final int line = source.substring(0, match.start).split('\n').length;
        offenders.add('${entity.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '這些呼叫點直接 push 了對話框 route，繞過 already-open 防護。\n'
          '改成 pushDialogRoute(context, …)（或 pushDialogRouteOn(router, …)）：\n'
          '${offenders.join('\n')}',
    );
  });
}
