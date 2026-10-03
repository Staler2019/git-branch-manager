# chore/s3-arch-structure — 第一個 rules 檔遷移：退役 arch-structure.md

## Situation

S2 之後 L0 是 90,584 字元，目標 30,000。最大的 `docs/rules/arch-structure.md`（29,612 字元、15 條 pin）
大半是路由樹、目錄清單這類重述程式碼的參考資料，以及使用者裁定的長篇理由。

## Task

用 `memory-steward` 產出逐條處置表，使用者裁定後套用。限制：被刪 pin 的所有引用都要改指向新位置
（程式碼 8 處、規則檔 2 處），且不能遺失任何事實。

## Action

- **memory-steward 第一次實跑**，15 條處置：L0 1（layering）、L1 1（未提交列不是 `ListView` 項）、
  ENCODE 3（已有測試守住）、PIN 7（裁定已有測試，程式碼加一行 `Ruling:`）、DELETE 3（過時）、
  L2 其餘。抽查關鍵事實皆屬實：路由實際多 3 個 worktree dialog（規則寫 22）、`PreferencesSection` 有 7 值
  （規則寫 6）、`features/` 多了 `app_lifecycle/`、`update/`、`wc.files`/`wc.stack` 有 `gbm_layout_test` 鎖住。
- **否決 steward 一項**：它提醒 `docs/rules/` 與 `.claude/rules/` 同名檔可能重複計算 —— #147 已刪掉那些
  `@import`，不成立。
- **使用者裁定**：處置表照套；`arch-structure.md` 只剩一條時併進 CLAUDE.md 並刪檔；「`workspace/widgets/`
  不依賴 Riverpod」我原建議留 L0 一行，使用者問「這什麼時候加的、為什麼，架構應該都是 Riverpod 在 hold」。
  查得是 2026-08-13 #34 加的，是 presentational/container 拆分（狀態仍由 `WorkspaceScreen` watch，往下傳值與
  callback），理由已寫在 `menu_bar_row.dart:15`、`tab_row.dart:49` 的 doc comment —— 是局部設計不是專案設定，
  ~~留 L0 一行~~ 收回，整條刪。
- **C1 紀錄**：10 份 STAR（7 ruling、3 history，records README 新增 `history` 類別）。
  `check-doc-migration-loss.py` 逐段比對 10 段原文：第一次 two-column 缺 `WorkingCopyDiffMode.unified`，
  補上後全部缺 0。該腳本對檔案最後一段會 `StopIteration` 崩潰，一行修好（以檔尾為界），對照組（只拿 README
  比對）確實報出缺漏。
- **C2 註解**：8 處 pin 引用改指紀錄；7 處裁定加一行 `Ruling:`。diff 中非註解行 0；`dart format` 0 變更、
  `flutter analyze` 0 issue。
- **C3+C4**（併成一個 commit，否則中間狀態 pin 重複）：layering 併入 CLAUDE.md；新增
  `.claude/rules/history-graph.md` 沿用原 pin `STRUCT-history-uncommitted-row`（pin 不改名，`fn-cpp-core` 的
  引用因此不動）；刪 `arch-structure.md`；README 前綴表就地劃掉。

## Result

- L0 **90,584 → 61,591** 字元，上限同步調低；pin 211 → 197，懸空 0；相對連結 broken 0。
- ENCODE/PIN 所依賴的 13 個測試檔實跑 +158 全過。
- 未做：L0 仍高於 30,000，下一個是 `arch-state-machine.md`（21,281）。L1 檔仍全數超過每檔 6,000。
