# claude/issue-159-9cdfa5 — capi 宣告與 Dart FFI typedef 的簽章 parity 測試（#159）

## Situation

`lookupFunction` 只比對 symbol 名稱（[TEST-ffi-matches-symbol-only]），`gbm_capi.h` 與
`gbm_bindings.dart` 的 `_XxxNative` 不同步時，analyze、unit、capi test 全綠，runtime 才壞 stack。
`integration_test/` 完全沒碰到 `gbm_rebase_start`（6 參數）與 cancel。

## Task

照 #159 方案 A：unit 層解析兩份原始碼比對，CI 每個 PR 都跑。方案 B（device 層 rebase/autosquash）
不在範圍（issue 自己寫明）。

## Action

- 實測（HEAD 115a3ad）：header 149 個 `^GBM_API`、bindings 148 個 `lookupFunction`、143 個
  `_…Native` typedef，無 `asFunction`／`.lookup<`，header 無 `/* */` 註解——與 issue 數字一致。
  header 的 C 型別共 15 種寫法（含 `const`／handle 別名），全部對到 issue 表內的 FFI 型別。
- 新增 `app_flutter/test/data/ffi/gbm_capi_signature_parity_test.dart`，6 個 test：解析健全性
  （GBM_API 數 − 2 個 `#define` = 解析數；lookup 數 = 解析數）、symbol 存在、參數數量、逐型別、
  未綁定 allowlist 恰好相等、callback。參數數量與型別拆成兩個 test，數量不符時型別 test 跳過該項，
  讓一個漂移只紅一個 test。
- 第一版在 `main()` 頂層呼叫 `expect` → `OutsideTestException`，改放 `setUpAll`。

### Mutation（全套 `flutter test`，每次由 scratchpad 備份還原）

| # | mutation | 結果 |
|---|---|---|
| M1 | 照 issue 字面：刪 `_RebaseStartNative` 的 `Int32 autosquash` | `-147`：本測試 1 個 + **146 個測試檔載入失敗** |
| M1h | header 刪 `gbm_rebase_start` 的 `int32_t autosquash` | `-1`：參數數量 test |
| M2h | header 把 `int32_t stashFirst` 改成 `const char*` | `-1`：逐型別 test |
| M3h | header 加未綁定的 `gbm_fake(void)` | `-1`：allowlist test |

**mutations-run = 4，tests-reddened = 147 / 1 / 1 / 1。**

- **issue 前提的更正**：M1 不窄，原因不是測試，而是 `lookupFunction<N, D>` 的**編譯期**檢查本來就
  比對 Native↔Dart——只改 Dart 端 Native typedef 會讓所有 import bindings 的測試檔編譯失敗。所以
  這條縫實際上只在 **C 端**：Dart 兩個 typedef 同步、header 不同步。M1h/M2h 是 issue 的 M1/M2
  在這條縫上的等價形狀，各自只紅本測試。

## Result

- C1 `0138170`：測試，analyze 0、format 0。
- C2：就地更正 [TEST-ffi-matches-symbol-only]（「only a device-tier test crosses that seam」劃線，
  改為數量／型別由本測試守住、同型別順序仍只有 device 層看得到，並記下 N↔D 編譯期檢查的量測），
  以及 [DRIFT-rebase-onto-missing-capi-flags] 的 Note 與 [DRIFT-cancel-capi-unwired] 的 Do。
- 未做：方案 B（issue 明列不在範圍）；`stashFirst`/`rebaseMerges`/`autosquash` 三個 `int32_t`
  互換仍無測試看得到。
