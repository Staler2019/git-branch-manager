# fix/crash-filter-stack-overflow-log — #214：stack overflow 時 crash log 遺失，先補證據

## Situation

`CrashFilterApiTest.AStackOverflowIsLoggedWithNoBox` 在 PR #213 的 Windows capi job 紅過一次（run 42506953083 attempt 1）：log 沒有那一行，marker 也不存在，子程序 0.35 s 就結束。#214 的推測是：溢位後剩下的 stack 不夠 filter 用，又 fault 了第二次，process 直接結束。當時沒有 exit code，也不知道失敗頻率。

## Task

使用者裁定「214 先做 1 再做 2」：

- 方向 1：補證據。
- 方向 2：stack overflow 時改由 helper thread 寫 log。

開始前約定：如果方向 1 的結果推翻推測，就停下來回報，不接著做方向 2。

## Action

- `edbaa820`（test），兩部分：
  - `CrashRun::describeExit()` 帶出子程序的 exit code、marker 是否存在、sentinel 剩多少 stack。這個測試的三個斷言都附上這段訊息。
  - `gbm_crash_now --stack-overflow [frame bytes]` 可以指定每層 frame 的大小（改用 `_alloca`，預設仍是 4096）。sentinel 用 `GetCurrentThreadStackLimits` 算出剩餘 stack，寫進 `<marker>.left`。數字是手寫轉換，沒有用 `snprintf`。
- 在 macOS 上用 `windows.h` stub 做 `-fsyntax-only`（[CI-platform-guarded-block-uncompiled]）。fixture 通過；測試檔只剩 stub 本來就沒宣告的 API 造成的錯誤。
- `5ca341de` 是暫時的 CI step，只跑 Windows，設 `continue-on-error`，讀完結果後由 `73e636c9` revert。內容是直接執行 fixture：
  - 預設 frame 跑 200 次。
  - frame 4096..8128（每 64 bytes 一組）各跑 4 次。
  - 另外把這個測試用 `--gtest_repeat=200` 重複跑。

## Result

量測數字（run 43012514518，`windows-latest` x64）：

| 條件 | 次數 | 結果 |
|---|---|---|
| 預設 frame | 200 | 全部 `0xC00000FD`，log 有那一行，marker = "after" |
| frame 4096..8128 × 4 | 256 | 同上 |
| 合計 | 456 | 0 次遺失 |

- sentinel 執行時的剩餘 stack（到保留區底端的距離）：最少 10,384 bytes，最多 17,808 bytes。同一個 frame 大小也會差到約 7 KB，表示每次 overflow 停的位置不同。
- 這個距離包含系統不給用的保留區尾端，所以真正能用的部分比這個數字小。實際小多少沒有量。
- `--gtest_repeat=200`：step 只保留了輸出的最後 40 次，這 40 次都通過，前面 160 次的結果看不到。這是量測 script 的疏漏。
- 同一個 job 的 ctest 裡，這個測試正常執行時間是 0.03 s；當初失敗的那次是 0.35 s。如果是第二次 fault，process 應該很快就結束，不會比正常慢。

量測結果不支持 #214 原本的推測。使用者裁定「只收證據，先停」：

- 方向 2 不做。
- #214 保持開著。下次失敗時從 `describeExit()` 的 exit code 判斷：
  - `0xC00000FD`：只 fault 一次。
  - 其他例外碼：處理 overflow 時又 fault 了一次。
  - 2：fixture 讀不到環境變數。
  - 3：`LoadLibraryExW` 失敗。
  - 2 和 3 都還沒開始 crash，log 和 marker 都不會寫出來，跟當初看到的症狀相符。
- 量測結果貼在 #214 的留言。

G2 與 mutation：

- `edbaa820` 只在失敗訊息裡加字，沒有新增斷言，所以沒有可以變紅的 mutation。mutation 執行 0 次，變紅 0 個。
- 它的作用要等真的失敗時，在失敗訊息裡才看得到。

`feat/stuck-waits` 的 ledger 裡記著這個推測，已經在原處補上量測結論。

### 追加：本機 Windows 重現嘗試

CI 那 456 次只直接執行 fixture，沒有照 CI 的順序跑整組 test；frame 也只量了 4096..8128。這次在本機補上這兩項，看能不能重現。

環境：Windows 11（build 26200）ARM64，是 Apple silicon 上的 VMware 虛擬機。`build/capi-only` 用 MSVC 14.51 Hostx64/x64 編譯，設定是 RelWithDebInfo。binary 是 x64，透過 Windows on ARM 的 x64 模擬執行，不是 CI 那種原生 x64。程式碼是本分支的 `bb015df6`。

| 條件 | 次數 | 失敗 |
|---|---|---|
| `ctest -R '^CrashFilterApiTest\.'` 照 CI 順序跑 7 個 test，無負載 | 100 輪 = 700 次 | 0 |
| 同上，另開 8 個 busy loop 佔滿 4 核 | 100 輪 = 700 次 | 0 |
| 直接執行 `gbm_crash_now --stack-overflow <frame>`，frame 256..4096，每 16 bytes 一組，每組 3 次 | 723 次 | 0 |

- 直接執行的 723 次，exit code 都是 `0xC00000FD`，log 裡都有 `code=0xc00000fd` 那一行，marker 都是 "after"。sentinel 的剩餘 stack 最少 10,672 bytes，CI 量到的是 10,384，兩者接近。
- 每個 ctest test 都是獨立的 `gbm_capi_tests.exe` process，`ProcessTempDir` 讓 log 和 marker 都放在 `gbm-proc-<pid>` 底下。CI 那次失敗時 ctest 也是依序執行（`tbase` 沒設 `jobs`），所以排除「前一個 test 刪掉這個 test 的檔案」。
- 結論不變：本機重現不出來，也沒有證據支持「第二次 fault」。#214 繼續等 CI 下次失敗，再用 `describeExit()` 的 exit code 判斷原因。
- 限制：x64 模擬執行和原生 x64 在 stack guard page、例外派送上可能不一樣，這組數字不能取代原生 x64 的量測。
