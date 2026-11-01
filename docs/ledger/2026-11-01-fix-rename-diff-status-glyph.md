# fix/rename-diff-status-glyph — rename 的 diff 與檔案列狀態 icon

## Situation

`git mv` 之後，diff pane 把檔案畫成整檔新增，Working Copy 也一樣。在 scratchpad repo 重現了根因：

```
git diff --cached -M -- b.txt         →  b.txt | 20 ++++++   (整檔新增)
git diff --cached -M -- a.txt b.txt   →  a.txt => b.txt | 0   (rename，0 hunk)
```

per-file diff 只把一個路徑當 pathspec，git 只看到半邊，rename 偵測就不會成立。同一個根因出現在五個呼叫點：

- WC 的 diff／full diff
- WC 的逐行／逐 hunk unstage：用錯的 hunk index，會 unstage 到錯的行
- History commit 檔案 diff
- Compare 檔案 diff：這裡另外沒帶 `-M`，結果跟著使用者的 `diff.renames` 設定走
- File History 選 rename commit：只送 `renamedFrom`，畫成整檔刪除

檔案清單本身已經帶了正確的 `oldPath`/`kind`，只是 UI 沒畫狀態。

## Task

使用者裁定：

- 「所有呼叫點全修」。
- 新增（含 untracked）畫 `+`，刪除畫 `-`，有移動屬性畫 move icon，其他照現狀；「+ and - use icon, not font」。
- 「+ - 移動icon固定占位，file name固定縮排」。
- 移動 icon 從八個候選裁定 B（lucide `arrow-right`），「不換顏色」。
- diff 標頭寫成 `old → new`。「三處都新增 old → new 標頭」，「要更新spec」。
- 「Compare 還沒選檔時不畫標頭、Stash 的標頭放在 diff 那一格的頂端 ok」。
- 純移動（0 hunk）在 body 畫一行說明，不畫 `No changes`；Working Copy「完全比照 binary」。
- 未 stage 的 `mv` 照 git 畫成 `- a`／`+ b`，不做配對。

## Action

十一個 commit，每個都可以單獨 revert：

| # | commit | 內容 | mutation（跑／紅） |
|---|---|---|---|
| 1 | `7156d1cc` | WC staged rename 的 diff／full diff 帶 oldPath；core 只留 `newPath == path` | C++ 2／3；Dart 4／6 |
| 2 | `a08fe13e` | 逐行／逐 hunk unstage 用同一個 pathspec 重建，並檢查形狀 | C++ 5／7；Dart 2／2 |
| 3 | `c6752315` | History commit 檔案 diff 帶 oldPath；cache key 納入兩個路徑 | C++ 4／6；Dart 4／3（存活的條件已刪除） |
| 4 | `4807cfd3` | Compare 帶 oldPath 與 `-M` | C++ 4／6；Dart 4／7 |
| 5 | `56fdd758` | File History 依各 commit 當時的路徑要 diff | C++ 3／5；Dart 4／6 |
| 6 | `fd341aa7` | `FileChangeGlyph` | 10／17 |
| 7 | `0ee1f6f8` | 設計稿 `docs/claude-design-demo/rename-diff-display-spec.html` | — |
| 8 | `8bfabedb` | 改用 `arrow-right`，icon 欄固定佔位 | 2／10 |
| 9 | `e1d5211e` | 抽出 `GbmDiffHeaderBar` | 2／4 |
| 10 | `cfc50e91` | `DiffFile.headerText`，五個面的標頭 | 7／15 |
| 11 | `30fde811` | `DiffFile.isPureRename`、`kPureRenameNote`，四處畫說明 | 7／9 |

偏離計畫的地方，照實記錄：

- **`FileHistoryEntry.path` 取代了計畫裡的 `renamedTo`。** 實作時發現，rename 之前的 commit 原本是用分頁上的新名字去要 diff，拿回來是空的。改成每筆 entry 帶自己 commit 裡的路徑，這個問題也一起修好。
- **Dart 端沒有重新篩檔。** core 已經只回 `newPath == path` 的那一個檔，篩選只做這一次（`working_copy_view.dart` 的 `_fileOf` 註解）。
- **`ChangedFilesPanel.onFileTap` 的簽章沒改。** 點檔時從 `commitFiles` 查出舊路徑。
- **slice 3 的 `ChangedFile.renamedFrom` 放置時沒有先問 arch-suggester。** 之後的 `headerText`、`GbmDiffHeaderBar`、`isPureRename` 都有先問。
- **計畫說 Compare／File History 的標頭「同規則」，這個前提不成立。** 這兩個面原本根本沒有標頭，由使用者裁定新增。
- **順序違規。** glyph（`fd341aa7`）先實作，設計稿（`0ee1f6f8`）後補，違反「沒有設計給我看過才做」。已向使用者回報，並寫進設計稿。

## Result

- **抽 `GbmDiffHeaderBar` 時順帶修好一個既有排版 bug。** 原本的 bar 用一個 `Flexible` 加一個 `Spacer`，兩個 flex 1 的子元件平分剩下的空間，路徑短時右側切換鈕停在 bar 的中段。改用 `Expanded` 包文字、不放 `Spacer`。把它改回去時，History 與 WC 的真實畫面測試都會紅（[FLU-renderflex-non-flex-first]）。
- **Stash 標頭的第一版測試是錯的。** 它假設檔案清單在 diff 上方。實際上清單是 split 的固定 pane，`fixedPaneEnd: trailing` 把它放在**下方**。量了 rect 才看出來（標頭 47–85、DiffPage 85–554、清單 581–719），測試已改正，程式不用動。
- **說明列 `text-tertiary` 的對比度只有 3.08（light）／4.12（dark），低於 4.5。** 這個顏色沿用 binary 提示的既有 token，照實回報、沒有改。
- **ctest 的 `index.lock` 紅燈是兩次 ctest 同時跑造成的。** 兩次執行共用以測試命名的 temp repo，形狀和 #194 相同。單獨重跑 962/962 全綠，那個 flaky 測試連跑 3 次也是 3/3。
- **更正了錯的註解。** `Session::emitWorkingCopyDiff` 與 `selectionCoversWholeAddedFile` 原本寫「舊路徑在前」，實際上 git 依路徑排序；rename 也不會再以 Added 出現。
- **數個 Dart mutation 寫成了編譯失敗。** slice 4 一個，slice 6 三個。這些都作廢、改成能編譯的形式重做，不計入上表。
- **verifier 第一輪判 REFUTED，抓到本輪自己引入的 P2。** `_stagedOldPath` 沒有檢查 `indexStatus`。設了 `status.renames=copies` 時，staged 的 copy 在 `oldPath` 也帶著來源路徑，core 用兩個路徑重建後得到一個 Added 檔，形狀檢查不通過，於是 copy 的逐行／逐 hunk unstage 每次都回「That change no longer exists」。verifier 用 capi probe 在真 repo 重現：帶 oldPath 失敗，不帶 oldPath 成功。修正方式是只有 `renamed` 才帶舊路徑，與 `ChangedFile.renamedFrom` 同一規則。補了 copy 的測試，mutation 跑 2 個、紅 7 個測試。
- **複驗 verifier 判 CONFIRMED，另報兩個 P4，使用者裁定「p4修掉」。**
  - **只選到未變更行時，逐行操作回的是 git 的 parse error。** 只選 context 行時，`buildLineSelectionPatch` 產生只有 context 的 patch，`git apply` 以 "corrupt patch" 拒絕，畫面顯示 "Git reported an error"。stage、unstage、discard 三個方向都一樣，不是 rename 才有的問題。修正後選取裡沒有 `+`/`-` 行就回傳空字串，StageOps 既有的檢查改回 "Nothing selected to …"。兩個以「空選取產生全 context patch」為前提的測試改寫成新的斷言。mutation 跑 3 個、紅 15 個測試；另有 2 個 mutation 因腳本的分隔字元寫壞、沒有編譯成功，已作廢重做。
  - **staged copy 按逐 hunk unstage 會把整檔移出 index。** 經使用者裁定「維持現狀」，不改程式。copy 依裁定照現狀顯示成整檔新增、只有一個 hunk，unstage 這個 hunk 就是 unstage 整個新增，結果和畫面一致，也是 git 原本的語意。
- 新規則：[GIT-rename-pathspec-needs-both-paths]。
