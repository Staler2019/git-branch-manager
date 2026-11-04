# chore/round-skills-and-wiring-auditor — G3、G4 的 skill 與 orphan wiring auditor

## Situation

G3、G4 的清單只靠記憶執行。`[CULT-orphan-wiring]` 已發生 19 次，其中跨語言的案例單靠 grep 很難抓到。

## Task

使用者同意做自動化建議的第 3、4、5 項：`/round-close`、`/g3-preflight`、`wiring-auditor`。

## Action

- 新增兩個只有使用者能觸發的 skill，流程引用既有 README 與 pin，不重寫規則本文。
- `wiring-auditor` 原本建議放全域，會讓角色名單變成十個。實作時改放專案層，因為內容綁這個 repo 的 C++、capi、Dart 分層，全域名單也不必改。
- 撰寫 G3 流程時發現 `[TEST-stale-process-blocks-tier]` 要求跑 `pkill -f`，已被使用者的 `block-fuzzy-kill.py` 拒絕，就地更正為 `pgrep` 確認後 `kill <PID>`。
- 失誤：這條更正第一次寫到主 checkout，發現後搬到這個 worktree，主 checkout 從 `git show HEAD:` 還原。

## Result

- `check-rule-pins.py`、`check-instruction-budget.py` 通過；兩個 skill 與 agent 引用的 10 個 pin 都對得上。
- 只驗證了 frontmatter 與引用，**skill 與 agent 都還沒實際跑過**：這個 session 的 agent 名單沒有 `wiring-auditor`，要合併並開新 session 才能驗證。
- 這輪只有文件與設定，沒有跑測試套件。
