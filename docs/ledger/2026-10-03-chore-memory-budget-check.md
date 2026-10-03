# chore/memory-budget-check — 開場指令量的上限與 L2 紀錄格式

## Situation

chore/path-scoped-rules 之後，開場載入降到 133,487 字元（專案 89,360 + `~/.claude` 44,127），
低於 Claude Code 的 150k 上限，但只剩約 16k 餘裕。使用者判斷「未來還是會超標」，並給出原則：
開場只放不常變的專案設定；bug、使用者偏好等紀錄要留，但有需要才去找；實作以 code 與當下判斷為準；
寫這麼多說明是 code 或架構沒寫好的訊號。

## Task

把這個原則變成會自己守住的機制，分三片（使用者裁定「照你建議」）：S1 建只讀的維護 agent、
S2 建檢查與紀錄骨架、S3 起一個 rules 檔一輪遷移。本輪是 S2。限制：L0 從 ~90k 降到目標 30k
本身就是 S3 的工作，所以 S2 的檢查不能一開始就用 30k，否則 CI 立刻紅。

## Action

- **S1（`~/.claude`，不進 repo）**：`memory-steward` agent（只讀，使用者裁定 1）、checklist
  （三層、預算、逐條決策樹、註解規則、STAR 範本）、`measure.py`。`measure.py` 在 `e3b6f78` 上量出
  21 檔 166,977 字元，與 Claude Code 警告的 21 檔 166.8k 相符（字元多算約 0.1%，偏保守）。
- **`scripts/check-instruction-budget.py`**：以字元計算 CLAUDE.md、遞迴 `@import`、無 `paths:`
  的 `.claude/rules/`；上限寫在 CLAUDE.md 的 `L0 ceiling`。**棘輪**：超過紅、低於實際量超過 2,000
  也紅，逼縮減時一併調低。只算專案這一份 —— CI 看不到使用者的 `~/.claude`。依路徑載入的檔只回報。
  放置由 arch-suggester 建議（`scripts/` 與 `check-rule-pins.py` 同層）。
- **TDD**：9 個測試先紅（腳本不存在）後綠。5 個 mutation，各紅 1 個測試：`has_paths` 恆 false、
  不跳過 code fence、拿掉棘輪下限、不遞迴 import、算 bytes 不算字元。
- **CLAUDE.md `## Memory filing`**：L0/L1/L2 三層、code 優先、新條目交 memory-steward 分類。
  上限先設為實測 90,307，接著 rules README 加上這支腳本的說明讓 L0 變 90,584 —— 檢查器當場擋下，
  上限在同一個 commit 調為 90,584。
- **L2 改用 STAR**（使用者裁定）：新增 `docs/records/`（裁定與 bug，一檔一則），
  `docs/ledger/README.md` 的新回合格式改為 STAR，舊寫法就地劃掉。本檔是第一份 STAR ledger。
- 被否決：一開始就以 30k 為上限（CI 立刻紅）；L1 也設棘輪（11 個檔全超，需要 11 個上限，
  留給 S3 隨遷移處理）。

## Result

- `python3 scripts/check-instruction-budget.py`：L0 90,584 / 上限 90,584，exit 0。
- pin 檢查懸空 0；相對連結 broken 0。`cq.yml` 的 YAML 本機無 `yaml` 模組可驗，以 CI 為準。
- 未完成：S3（逐檔遷移把 L0 降到 30k、L1 每檔 6k）；`memory-steward` 尚未實際跑過一次
  （建立它的那個 session 看不到新 agent）。
