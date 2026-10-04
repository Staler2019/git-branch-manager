# chore/s3-l1-toolchain-ci — L1 第六片：ops-toolchain-ci.md 14 條縮為 4 條

## Situation

`.claude/rules/ops-toolchain-ci.md` 有 14 條。它的 paths 涵蓋 `.github/**`、`scripts/**`、CMake 與三個平台的 runner，碰到任一檔就整份載入。好幾條的前提是「flutter-ci 只跑 ubuntu」，但 #69 已關閉、CI 已是三 OS matrix，這些前提已不成立。

## Task

依 `memory-steward` 的處置表縮減。使用者裁定「照你建議做」，包括 `[CI-dart-sdk-floor]` 的「四個 pin 要一起動」維持寫成規則，不擴充 `cq.yml` 的 lint。

## Action

- **事實核對**：steward 據以下結論的事實逐項對過原始檔。
  - `ci.yml:170` 寫明不再跑 `build_capi`，所以 `[CI-linux-only]` 剩下的那句也不成立。
  - `cq.yml:153` 有 `powershell-parse` job。
  - `.gitattributes:28` 有 `*.golden -text`。
  - `CMakePresets.json:62` 的 `tbase` 設了 timeout，有五個 preset 繼承它。
  - `update_installer_test.dart:710-713` 驗 CWD，`:723-728` 驗 BOM。
  - `.pre-commit-config.yaml` 說 lint job 在 `ci.yml`，實際在 `cq.yml`。
- **C1，只動註解**：
  - 更正 `cq.yml` 與 `update_installer.dart` 的「ubuntu-only／CI 沒有 Windows」。
  - 更正 `.pre-commit-config.yaml` 的 lint 位置。
  - `ci.yml`、`.gitattributes`、`drift-open.md`、orphan-wiring record 原本引用即將退役的 pin，改指向強制它的 job 或測試。
  - 這條分支先等 #158 合併、fast-forward 到 main 後才改 `drift-open.md`，避免兩支 PR 改同一檔。
- **C2，規則檔**：
  - 留 4 條並精簡。
  - 刪 5 條，因為 workflow、`.gitattributes` 或測試已在強制。
  - 刪 4 條，因為現場註解已經寫了原因。
  - `newer-flutter-dirties-tracked-files` 移到這裡，仍成立的那一句併進 `formatter-version-drift`。
  - `check-rule-pins.py`：112 條規則，懸空 0。
- **migration-loss**：逐條跑，缺項分成三類。
  - **補回規則**：`BUILD_TESTING`（`include(CTest)` 會帶進它，和 `GBM_BUILD_TESTS` 打架）。
  - **假陽性**：ledger 連結路徑，以及寫法換掉的 `ParseFile`、`verbosity`。
  - **移到這份 ledger 保存**：見下方「保存的做法」。

## 保存的做法（原規則裡、現場註解沒寫的部分）

- **byte 比對的 fixture**：
  - 用 `git ls-files --eol <path>` 驗證，必須印出 `attr/-text`，不是空的 `attr/`。
  - 用 `git show HEAD:<path> | tr -dc '\r' | wc -c` 確認 blob 本來就是 LF。
  - 已經以 CRLF 存進 repo 的 fixture，還要另外跑 `git add --renormalize`。
  - 本機重現的方法：把 blob 經過 `.replace(b'\n', b'\r\n')`，byte 77 會是 13 而不是 10，正好是斷言印出的兩個數字。
- **Windows 工具鏈**：新的效能 job 先從 build log 讀出實際用的編譯器路徑（`C:\mingw64\bin\c++.exe` 還是 `cl.exe`），不要從 `runs-on` 推斷。
- **本機 SDK 與 pin 不同時**：先把 `git diff` 存成 scratchpad 的 patch，再用 `git apply -R` 從那份 patch 還原，不用 `git checkout --`。

## Result

- `ops-toolchain-ci.md` 精簡為 3,668 字元，在 6k 預算內。
- L0 不變，維持 28,705。
- 還超過 6k 的 L1 剩 6 份：`fn-refs-branches`、`ops-spec-reading`、`fn-flutter-input`、`fn-flutter-state`、`arch-testing-device`、`arch-testing`。
  - `arch-testing` 是第三片之後超的：flutter-upgrade 那一輪加了 `[TEST-golden-no-glyphs]`，從 5,982 變成 6,617。
