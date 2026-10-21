# feature/make-select-branch-space-no-hiding — 選取列保留空間、TAGS/STASH 可收合

## Situation

選取 branch 之後，`SidebarPanel` 才在 filter 與 tree 之間插入 `BranchSelectionActionBar`
（`if (selection.isNotEmpty)`），整棵 tree 往下推 25px。單擊就算選取（P13 MULTIKEYS），
所以第一次點擊之後、正要右鍵開更多選項時，目標已經移開。TAGS / STASH 兩段也沒有辦法收合。

## Task

使用者裁定（2026-10-18）：
- (a) 選取列留在上方，**永遠保留固定高度**，沒有選取時是空白。
- (b) TAGS/STASH 比照資料夾規則：chevron 切換、per-repo session 記憶、filter 中強制展開、
  清空 filter 後回到原狀態、預設展開、標題帶數量。
- (c) 先更新 spec、寫出 TDD 計畫，再實作。
- D1 = B：選取列採用 P13 callout 6 的 `surface-panel-raised` 底色與 `border-top`。I1–I3 照用。

## Action

- **C0 spec**：`docs/claude-design-demo/sidebar-selection-collapse-spec.html`（Artifact v1→v3）。
  spec-auditor 稽核了 7 個值：6 MATCH、1 NO-SOURCE（數量樣式，改為列入 Inferred I3）、0 CONTRADICTED。
  六項稽核：標籤配對 0 錯、token 覆蓋 0 未定義／0 沒用到。對比：`textTertiary` 用在 panel 上，dark 是 4.12、
  light-ide 是 3.08，都低於 4.5。這是現有 token 的問題，只回報，沒有修。
  - 第一版的 D1 問題寫得讓人看不懂（使用者：「p13應該只有branch, tag select區塊，沒有tags, stash大標題」），
    第二版改寫成「D1 只和選取列有關」，並加上 A/B 兩個樣本。
  - P13 的 mockup 把計數列畫在清單**底部**，但沒有 prose 規定位置；位置依裁定 (a) 放在上方。
- **C1** `SidebarPanel` 改成固定 `SizedBox(key: selectionSlotKey, height: space6)` 承載選取列；
  bar 加上底色與上框線，拿掉垂直 padding。
- **C2** `sidebarCollapsedSectionsProvider`（`lib/data/repositories/sidebar_collapsed_sections_repository.dart`，
  位置與命名來自 arch-suggester），形狀和 `branchFilterQueryProvider` 相同。
- **C3** `SidebarSectionLabel` 加上 `count`/`isExpanded`/`onToggle`；兩個 section 讀 provider，並接收
  `forceExpanded: isFiltering`。`sidebar_filter_test.dart` 抽出 `_pumpHideable`，原本的 remount 測試也改用它。

## Result

| Commit | 新測試 | 先紅 | mutations-run | tests-reddened |
|---|---|---|---|---|
| C1 `eb9e4012` | 4 | -3（最小寬度那條是控制組，原本就綠） | 3 | 4（M1→2、M2→1、M3→1，都只紅預期的那幾條） |
| C2 `5ff369b9` | 2 | 編譯紅（新符號，無法避免） | 1 | 2（共用且非空的 set 同時打中兩條） |
| C3 `04106d82` | 9 | -5（「再點一次會出現」與「query 強制展開」在實作前是空轉的綠） | 5 | 7 |

- **用跑的才找到的問題**：C3 的 M2（provider 改成 autoDispose）第一次跑多紅了一條「清空 query 回到收合」。
  原因是 `forceExpanded || !ref.watch(...)` 這個寫法在有 query 時會短路，整段期間沒有任何 listener。
  改成一律 watch 之後，M2 只紅「隱藏 sidebar 後仍收合」那一條。
- 全套 `flutter test`：+3920 ~8，全綠；`flutter analyze` 0；`dart format` 無差異。
- **Device tier**（用 grep 找出會碰 sidebar 的 5 個檔，`-d macos` 一個檔一個檔跑）：merge_current、merge_squash、
  repo_lifecycle、rebase_onto 都綠。**`prepared_message_flow_test` 紅**（+4 -1），本分支兩次都紅在
  「a conflicted merge overwrites the typed text…」：`Merge` 按鈕找不到。在 origin/main `4f428b9c`
  的暫時 worktree 上跑同一個檔**也是紅**，紅在同一條測試，但斷言不同（`Expected: 'my body' / Actual: ''`）。
  所以這條在本輪之前就已經是紅的，不是本輪造成的；**沒有開 issue**，等使用者決定。
- **實際 app 驗證沒有完成**：debug app 的視窗在另一個 Space，`cliclick` 是用螢幕座標點擊，點不到；
  debug app 又自動開了 device test 留下的暫存 repo，畫面上是「No branches」。只用 `screencapture -l <window id>`
  對該視窗截了一張圖，沒有走完選取與收合的流程。
- **沒有新增 pin**：「會出現/消失的列要保留 slot」已經由 C1 的測試（tree 的 rect 前後相等）強制，
  依 CLAUDE.md「能用測試強制的陷阱就寫在測試裡」，所以不寫成規則。
