// 使用者裁定推翻本輪原本的「九個 singleton 面板的 splitter id 刻意不改」。
//
// 那個裁決留下的不是一個壞掉的行為，是一個**例外**：三種面板寫
// `panel.<kind>:<path>`，九種寫 `panel.<kind>`，十三個字串全部手寫，而且有一
// 支測試站在那裡說「singleton 保留沒有後綴的 id」——讀起來像一條被祝福的豁免，
// 下一輪照著它加第十四個面板時沒有任何東西會攔住打錯的字。
//
// 換掉例外的方式不是把九個改成有後綴（那只是把不一致搬個位置，還會把每個人存
// 過的寬度變成孤兒），而是讓十二個都從**同一個函式**拿 id，並且讓那個函式的規
// 則來自 `GbmPanelKind.isPerSubject` ——`open()` 用來判斷「同一種面板能不能同
// 時開兩個」的正是同一個屬性。於是「能不能有兩個分頁」與「id 分不分得開」變成
// 同一個事實的兩面，而不是兩個要互相記得的決定。
//
// **刻意不用分頁 id 當 key。** 那是字面上最大的讀法，而且是錯的：分頁 id 是
// `'${kind.slug}-${_nextId++}'`，一個記憶體裡的計數器，`PanelTabsNotifier` 沒
// 有持久化任何東西。拿它當 key 會讓 splitter 寬度跨重啟完全存不下來，更糟的是
// 會**撞號**——這次的 `blame-0` 下次可能是另一個檔案，於是繼承到別人的寬度。
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';
import 'package:gbm_flutter/features/panels/panel_storage_id.dart';

void main() {
  group('panelStorageId', () {
    test('every panel kind gets a different id', () {
      final List<String> ids = <String>[
        for (final GbmPanelKind kind in GbmPanelKind.values)
          panelStorageId(kind, subject: 'lib/a.dart'),
      ];

      // Two panels sharing an id share a splitter position, silently. Nothing
      // else in the app would report it.
      expect(
        ids.toSet().length,
        GbmPanelKind.values.length,
        reason: 'two panel kinds resolve to the same storage id',
      );
    });

    test('a per-subject kind is distinguished by its subject', () {
      final GbmPanelKind kind = GbmPanelKind.values.firstWhere(
        (GbmPanelKind k) => k.isPerSubject,
      );
      expect(
        panelStorageId(kind, subject: 'lib/a.dart'),
        isNot(panelStorageId(kind, subject: 'lib/b.dart')),
      );
    });

    // The rule with no exception in it: the suffix is present exactly when
    // the kind can have more than one tab, which is the same property
    // `PanelTabsNotifier.open()` dedupes on.
    test(
      'a singleton kind ignores a subject, because it can never have one',
      () {
        final GbmPanelKind kind = GbmPanelKind.values.firstWhere(
          (GbmPanelKind k) => !k.isPerSubject,
        );
        expect(
          panelStorageId(kind, subject: 'lib/a.dart'),
          panelStorageId(kind),
          reason:
              'open() normalises a singleton kind\'s subject to null, so an id '
              'that varied with it would key on something no tab can hold',
        );
      },
    );

    test('a slot names a second splitter inside one panel', () {
      final GbmPanelKind kind = GbmPanelKind.manageStashes;
      expect(panelStorageId(kind, slot: 'detail'), isNot(panelStorageId(kind)));
      expect(
        panelStorageId(kind, slot: 'detail'),
        startsWith(panelStorageId(kind)),
      );
    });

    // The stem is `slug`, not a second naming switch beside it. That is the
    // whole point: a panel kind already has exactly one name in this codebase
    // and the storage id is now spelled from it, so there is nothing left to
    // keep in step. A parallel `storageStem` switch would have preserved
    // three more stored widths and re-created, in one file, precisely the
    // drift this commit removes from twelve.
    test('the id is `panel.` plus the kind\'s existing slug', () {
      for (final GbmPanelKind kind in GbmPanelKind.values) {
        expect(panelStorageId(kind), 'panel.${kind.slug}');
      }
    });

    // Nine of the twelve keep the exact string they were writing by hand, so
    // nine users' stored widths survive untouched. `interactive-rebase` is
    // the one singleton that re-keys (`panel.interactiveRebase` ->
    // `panel.interactive-rebase`) and its stored width is orphaned -- a
    // read-miss falling back to the default, never a wrong number. The two
    // per-subject history panels re-key too, but theirs were already orphaned
    // by this round's earlier per-subject change, so they cost nothing again.
    test('nine of the twelve ids are byte-identical to the old ones', () {
      const Map<GbmPanelKind, String> unchanged = <GbmPanelKind, String>{
        GbmPanelKind.manageStashes: 'panel.stashes',
        GbmPanelKind.manageWorktrees: 'panel.worktrees',
        GbmPanelKind.manageRemotes: 'panel.remotes',
        GbmPanelKind.manageSubmodules: 'panel.submodules',
        GbmPanelKind.manageLfs: 'panel.lfs',
        GbmPanelKind.patches: 'panel.patches',
        GbmPanelKind.bisect: 'panel.bisect',
        GbmPanelKind.reflog: 'panel.reflog',
        GbmPanelKind.blame: 'panel.blame',
      };
      unchanged.forEach((GbmPanelKind kind, String id) {
        expect(panelStorageId(kind), id);
      });
      expect(
        panelStorageId(GbmPanelKind.manageStashes, slot: 'detail'),
        'panel.stashes.detail',
      );
      expect(
        panelStorageId(GbmPanelKind.blame, subject: 'lib/a.dart'),
        'panel.blame:lib/a.dart',
      );
    });
  });
}
