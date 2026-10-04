# feature/issue159 — gbm_capi.h 與 Dart FFI typedef 的簽章 parity 測試（#159）

## Situation

`dart:ffi` 的 `lookupFunction` 只比對 symbol 名稱（[TEST-ffi-matches-symbol-only]）。`gbm_capi.h` 改了參數而 `gbm_bindings.dart` 沒跟上時，analyze、unit、capi test 都綠，runtime 才 corrupt stack。`integration_test/` 完全沒有碰到 `gbm_rebase_start`（6 個參數）和 cancel。

## Task

照 #159 的方案 A：unit 層文字解析比對，CI 每個 PR 都跑。驗收：測試先綠；至少兩個 mutation（刪 `_RebaseStartNative` 一個參數、某個 `Int32` 改 `Pointer<Utf8>`），每個只紅這個測試；mutations-run 與 tests-reddened 分開記；同型別參數換位抓不到這件事寫進註解。方案 B（device 層）不在範圍。

## Action

- 新增 `app_flutter/test/data/ffi/gbm_capi_signature_parity_test.dart`，不 import bindings，純讀兩個檔：
  - header 先去註解，抓 `GBM_API <ret> gbm_xxx(<params>);`；參數型別用「最長已知型別前綴 + 可有可無的參數名」辨識，因為 header 有無名參數（`GbmSessionHandle`、`int32_t`、`const uint32_t*` 等）。
  - 型別對照表照 issue 的 13 種，表外型別直接 `fail`。
  - 每個 `lookupFunction` 一個 `test`（名稱就是 symbol），比對參數數量、回傳、逐一參數。
  - 結構檢查：解析數量 = `GBM_API` 出現次數減 `#define`（149）、= `lookupFunction<` 出現次數（148），避免 parser 漏抓而假綠；未綁定集合必須恰好等於 allowlist `{gbm_cancel_operation}`；`GbmEventCallback` 對 `GbmEventCallbackNative`。
  - 第一版在 `main()` 宣告期呼叫 `expect`，`OutsideTestException` 整檔載入失敗。改成宣告期只 `throw StateError`，header 解析用 `late final` 延到 test 內。
- **Mutation，親眼讀 progress line 的 `-N`：**

  | # | 改哪裡 | 範圍 | 結果 |
  |---|---|---|---|
  | M1 | `_RebaseStartNative` 刪 `autosquash`（issue 字面） | 全量 | `+1700 ~1 -147`：analyzer `must_be_a_subtype`，146 個測試檔載入失敗 + parity 1 |
  | M2 | `_RebaseStartNative` 的 `stashFirst` `Int32`→`Pointer<Utf8>`（issue 字面） | 全量 | `+1700 ~1 -147`，同上 |
  | H1 | header `gbm_rebase_start` 刪 `autosquash` | 全量 | `+3151 ~1 -1`，只紅 `gbm_rebase_start`（參數數量 5 vs 6） |
  | H2 | header `stashFirst` `int32_t`→`const char*` | 全量 | `+3151 ~1 -1`，只紅 `gbm_rebase_start`（參數 4） |
  | H3 | header 新增未綁定 `gbm_new_thing` | 只跑本檔 | `-1`，只紅 coverage 那個 test |
  | H4 | header 加一個 `float` 參數 | 只跑本檔 | 每個 test 都紅，訊息都是「`float x` has a type missing from _cToFfi」 |

  mutations-run：6。tests-reddened：M1/M2 各 147、H1/H2 各 1、H3 1、H4 = 本檔全部。
- 每次 mutation 前把檔案複製到 scratchpad，從副本還原。
- 規則就地更正：`[TEST-ffi-matches-symbol-only]` 的「只有 device 層」、~~`[DRIFT-rebase-onto-missing-capi-flags]` 的「nothing today would catch」、`[DRIFT-cancel-capi-unwired]` 的「unit-tests clean」都劃掉重寫。~~ **更正（merge main 時）**：#158 已把 `drift-open.md` 由 14 條縮為 8 條，`[DRIFT-rebase-onto-missing-capi-flags]` 已退役，所以那一句的更正隨之消失；`[DRIFT-cancel-capi-unwired]` 改在 main 縮減後的「Only a device test crosses the seam」上就地劃掉重寫。
- 開 PR #162 後 CI 沒跑：PR 與 main 衝突（`mergeable: CONFLICTING`），GitHub 不替衝突中的 PR 觸發 `pull_request` workflow。用 merge（不 force-push）解掉。同一個 issue 另有一個 PR #161（`claude/issue-159-9cdfa5`），已是 closed、沒有合併。

## Result

- 基準：`flutter analyze` 0、`dart format` 無變更、全量 `+3152 ~1` 全綠。
- **issue 的前提有一半沒通過實測**：issue 說 mutation「只紅這個測試」，但只改 `_XxxNative` 的話，`lookupFunction<Native, Dart>` 的編譯期子型別檢查先抓到，analyzer 會報錯、146 個檔載入失敗。這種 drift 本來就不需要這個測試。這個測試真正補上的縫，是 header 改了而兩個 Dart typedef 都沒動（H1/H2），這種情況下只有它會紅，而且紅得很窄。issue 字面的 mutation 照做並如實記錄（M1/M2），另外補做 header 側的 mutation（H1/H2）來驗證窄紅。
- H4 不是窄紅：`late final` 的初始化丟例外後，每次存取都會重跑，所以每個 test 都紅。訊息精確，指名哪個參數，所以保留。
- 已知限制寫在測試註解：同型別參數換位（`rebaseMerges` ↔ `autosquash`）抓不到，要靠方案 B。
- 沒做的：allowlist 反方向（`gbm_cancel_operation` 被綁了而 allowlist 沒刪）沒有跑 mutation，因為要寫整組 typedef。邏輯上那是同一個集合相等斷言，H3 已經證明它會紅。
