# A file list's leaf label comes from FileListModeSwitcher; in tree mode folders stack and files do not

- **Kind**: ruling · **Pins**: was `STRUCT-leaf-label-from-switcher` · **Code**: `FileListModeSwitcher.leafBuilder`, `file_tree.dart` `_collapseIfSingleChild`

## Situation
Leaf rows read the path off the item itself, so list and tree mode drew the same string — on **all six** surfaces at once: Working Copy's two columns, History's Changed files, Compare's Files, the Conflict window and `panel_file_diff_detail`. Tree mode nested the row under a folder row and spelled the prefix again, so 「摺成樹狀」 bought indentation and nothing else. P03 item 10: 「平鋪完整路徑，或依資料夾摺成樹狀」.

## Task
Make the two modes differ, at one place rather than six call sites ([CULT-single-source-of-truth]).

## Action
- `leafBuilder(context, item, label)` takes the label as a third argument: list mode passes `pathOf(item)`, tree mode passes `node.name`. The parameter makes a wrong call site a compile error.
- ~~`_collapseIfSingleChild` keeps the whole concatenated prefix in `name` when it collapses a chain down to a **file**~~ — **overruled the next day, 使用者裁定**: 「樹狀模式下，我想要的是像 vscode 一樣，folder 可以堆疊名稱，但是檔案不會有 folder」. A chain of single-child folders still stacks into one row (P03-10's 「只有一個子項的資料夾會自動串接成 `lib/app/views` 一列」); the collapse **stops at the file**, which gets a real folder row and its bare basename. VS Code's `explorer.compactFolders` is the same rule.
- A folder's `displayPath` is root-anchored (`parentPath/label`) while `name` is only its label. `FileTreeList` keys expand/collapse on `displayPath`; a level-local prefix made `lib/features` and `test/features` share one key.
- Fixture: any nested file now tells the modes apart. The multi-child fixture is still what the `displayPath` rule needs — a single-child folder is collapsed into its parent, which anchors its prefix and hides the shared-key defect ([TEST-fixture-cannot-disagree]).

## Result
Signature enforced by the compiler; `file_tree_test.dart` 「a folder holding one file keeps its own row」 pins the stop-at-file ruling. Evidence: [ledger: Working Copy 檔案清單改成左側垂直](../ledger/2026-09-05-feat-working-copy-vertical-file-lists.md); [ledger: 追加三，樹狀模式改成 VS Code 語意](../ledger/2026-09-05-fix-working-copy-unified-single-view.md).
