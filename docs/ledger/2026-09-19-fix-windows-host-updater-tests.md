# 2026-09-19 · fix/windows-host-updater-tests — 第一次在 Windows 主機上跑測試

使用者要求：「run the tests to test windows platform of this project（之前只在 macOS 上測過）」，
跑完後再要求「修掉那三個 Windows 測試失敗」。

## 第一輪：Windows 上各層的實際結果

環境：Windows 11 24H2、VS 2022 Community（MSVC 14.44.35207）、CMake 3.26、Flutter 3.47.5。

| 層 | 指令 | 結果 |
|---|---|---|
| C++ core + capi | `cmake --workflow --preset capi-only`（先 `vcvars64.bat`） | 690/690 過 |
| 靜態分析 | `flutter analyze` | 0 issues |
| Dart 單元／widget／integration | `flutter test` | +2867 ~22 **-58** |
| 裝置層 | `flutter test integration_test/<file>.dart -d windows`，14 檔逐一跑 | 14/14 過（29 個測試） |

- 編譯器是 MSVC，從 `CMakeCache.txt` 的 `CMAKE_CXX_COMPILER` 讀出，沒有從 `runs-on` 推論
  （本機另有 TDM-GCC；[CI-windows-toolchain-not-implied]）。
- 裝置層包含 `update_check_flow_test`，它對真實 GitHub release 下載並驗 sha256，5m31s。
- **58 個紅全在四個檔案，且全是 updater**：`update_installer_test` 52、`update_leftover_sweep_test` 4、
  `update_script_golden_test` 1、`update_controller_test` 1。

## 58 個紅其實是兩個原因

把 Git 的 `usr\bin` 加進 PATH 重跑同四個檔案：**58 → 3**。

```
58 紅 ─┬─ 55：PowerShell 的 PATH 上沒有 chmod / touch   （ProcessException，setUp/tearDown 就炸）
       └─  3：加上 coreutils 後仍紅
              ├─ update_script_golden_test        golden 比對 byte 1593 不同
              ├─ update_installer_test            「install directory cannot be written」
              └─ update_controller_test           「an unwritable install directory is reported」
```

三個的成因各不相同，也都不是產品 bug：

1. **golden**：`_executableName()` 用 `Platform.pathSeparator` 切。測試刻意傳 POSIX 形狀的
   `/opt/gbm-example/gbm_flutter.exe`（golden 要每台機器一致），Windows 主機切不開，整條路徑被寫進
   `Join-Path $target '...'`。測試檔自己的註解寫著「installTarget() splits on the *host's* separator」，
   也就是這個限制早就知道，只是沒人在 Windows 主機上跑過。
2. **兩個 unwritable**：用 `chmod 555` 讓目錄不可寫。NTFS 不看 mode bit，所以在 Windows 上即使有
   `chmod` 也**完全不生效**——加了 coreutils 之後測試是「真的紅」，不是「跑不起來」。
3. 第 55 個之外的補充：`update_leftover_sweep_test` 的「survives a backup it cannot delete」在
   加了 coreutils 之後**反而是綠的**，但那是空轉的綠——`chmod 555` 沒生效，`deleteSync` 根本沒失敗過，
   `completes` 當然成立（[TEST-fixture-cannot-disagree] 的「fixture 表達不出失敗條件」一型）。
   這條是修 55 個時才查出來的，不在使用者點名的「三個」裡，但同一個根因，所以一起處理。

## 量測（先量再決定）

在 Windows 上實測哪些「讓操作失敗」的機制真的有效（scratchpad 的 `exp_delete.dart`）：

| 機制 | 結果 |
|---|---|
| 目錄內有一個被開著的檔案，再 `deleteSync(recursive: true)` | 丟 errno 32（sharing violation）✔ |
| 檔案內設 read-only 屬性（`attrib +R`）再遞迴刪 | **刪得掉**，不丟 ✘ |
| 寫入一個不存在的父目錄／以檔案當父目錄 | 兩者都丟 errno 3 ✔ |
| `File(dir).setLastModifiedSync(...)` 對目錄 | 丟 errno 50 ✘（Dart 沒有目錄 mtime setter） |

read-only 屬性那條是我本來會選的做法，量了才知道不行。

## 實作（四個可各自 revert 的 commit）

1. **fix: 可執行檔名依目標 OS 的分隔符切** — `_executableName()` 依 `_os`：windows 用 `[/\\]`，其餘只切 `/`。
   真實環境 host 與 `_os` 相同，行為不變。新增四個測試，包含「Linux 檔名內的反斜線要保留」，
   專門擋「一律兩種都切」的偷懶修法。
2. **test: 不可寫入目錄改用不存在的父目錄** — 兩個測試的 fixture 都改，同時移除
   `update_installer_test` tearDown 裡的 `chmod -R u+w`（不再有任何測試造出唯讀目錄）。
   這個 fixture 對 uid 0 也有效——`update_log_test.dart` 早就寫過同一個論點。
3. **test: leftover sweep 不靠 touch/chmod** — 目錄年齡改成移動注入的 `now`
   （`_clockAfter(entry, age)`：`now = entry.mtime + age`；只有 `now - mtime` 有意義），刪不掉的備份
   依 OS 選機制（`_makeUndeletable`：Windows 握住一個開啟中的檔案，POSIX 維持 `chmod 555`）。
4. **docs** — 本檔、INDEX 一行、兩條規則。

## Mutation 檢查

紅的數字都是從進度行的 `+N -M` 親眼讀的，不經 grep 或 helper。**mutation 數與紅測試數分開記**：

| Commit | 跑了幾個 mutation | 各自讓幾個測試轉紅 |
|---|---|---|
| 1 | 3 | 3 / 1 / 1 |
| 2 | 1 | 2 |
| 3 | 3 | 1 / 1 / 1 |

- C1：M1 改回 `Platform.pathSeparator` → 3；M2 一律兩種分隔符 → 1（只有反斜線那個）；
  M3 windows 也只切 `/` → 1（只有 `C:\...` 那個）。
- C2：`_isWritable` 的 catch 改回 `return true` → 恰好 `+94 -2`，就是兩個目標測試。
- C3：M6 拿掉年齡守衛 → 只有「leaves a recent one alone」；M7 讓 `_deleteQuietly` 不再吞
  `FileSystemException`（改 catch `ArgumentError`）→ 只有「survives a backup it cannot delete」；
  M8 拿掉名稱前綴守衛 → 只有「leaves unrelated temp directories alone」。
  **M7 就是「Windows 的 fixture 真的會失敗」的證據**——舊的 `chmod` 版在這個 mutation 下會維持綠。
- **第一次 mutation 全部沒套用**：helper 用 pyenv 的 `python.bat`，cmd 把參數裡的括號吞掉，
  回報「`.last was unexpected at this time.`」，三個 mutation 一個都沒動到檔案，`&& run` 因此
  也沒跑。改用 PowerShell 的 .NET `Replace`、並先斷言 `count(old) == 1` 才重做。

## 最終驗證（PATH 上沒有 chmod / touch）

`flutter test` 全套：**+2930 ~22，0 失敗**（2867 + 原本的 58 = 2925，加新增的 5 個 = 2930）。

## 沒做／開著的

- **Flutter 單元層仍然沒有 Windows CI job**（`ci.yml` 的 `flutter-ci` 只跑 ubuntu-22.04）。這三個測試日後
  仍可能無聲退化；加一個 job 是使用者的決定，本輪沒動。
- `installTarget()` 那個測試的 `isNot(contains('gbm_flutter.exe'))` 在 POSIX 主機上是空轉的
  （`File(r'C:\...').parent` 是 `.`），沒改，只記在這裡。
- 本機 `core.autocrlf=input`，CI 的 Windows runner 是 `true`；`[GIT-apply-without-cached-follows-autocrlf]`
  那類測試在這台機器沒走到 CI 的設定。
- **本機 Flutter 3.47.5 vs CI 釘的 3.44.9**：`flutter pub get`／`flutter test` 會改
  `pubspec.lock` 與 `analysis_options.yaml`（見 [CI-newer-flutter-dirties-tracked-files]）。
  本輪 stage by file，兩個檔案沒有進任何 commit，結束前用先存的 patch 反向還原。
- 環境：`commit.gpgsign=true`，第一個 `git commit` 在 pinentry 等 passphrase 時卡在背景；
  沒有用 `--no-gpg-sign` 繞過，等使用者解鎖後三個 commit 的簽章狀態都是 `G`。
- **沒有逐個 commit checkout 測過**（G3 的「fixture 在 commit 之間搬移才需要」）。C1、C2、C3 的檔案
  互不重疊、沒有共用 fixture 搬移，所以只在開發當下各自跑過目標測試，並在 HEAD 跑過全套；
  這一步是判斷過不需要而跳過，不是做過。
