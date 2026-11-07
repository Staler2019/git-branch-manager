# chore/clang-format-22 — clang-format 18 → 22.1.8，resolver 在 Windows 可用

## Situation

PR #210 review 時在 Windows 11 ARM64 本機跑格式檢查，`scripts/_resolve-clang-format.sh` 失敗：

- 它固定找 `venv/bin/pip`，但 Windows 的 Python 建出的 venv 執行檔在 `Scripts\`，所以 exit 127。
- 即使路徑對了，PyPI 的 `clang-format==18.1.8` 也沒有 `win_arm64` wheel，pip 會改成從原始碼編譯，結果失敗。
- `scripts/test_resolve_clang_format.py` 在 Windows 上 4 個全 error：`os.symlink` 在沒有開發人員模式時 WinError 1314。

使用者裁定：升到 22.1.8、一起修 Windows resolver、另開分支與 PR。

## Task

- CI、pre-commit、resolver 改用同一個 22 版本，`src/` 在 22 下保持乾淨。
- resolver 在 Windows（`Scripts\`）與 POSIX（`bin/`）都能自舉。
- resolver 的測試在 Windows 上能跑、能紅。

## Action

選 22 而不是 23 的依據（實測）：

| 項目 | 結果 |
|---|---|
| `jidicula/clang-format-action` v4.18.0 支援的 major | 3–22（README「Major versions supported」），23 不支援 |
| PyPI `clang-format` 22.1.8 | 有 `win_arm64`、`win_amd64`、macOS、manylinux x86_64／aarch64 wheel |
| `pre-commit/mirrors-clang-format` | 有 `v22.1.8` tag |
| 22.1.8 對 `src/` 的影響 | 201 個檔中 2 個要改，共 5 處：`struct stat st {}` → `st{}`（`FsUtil.cpp` 4 處、`CatFileBatch.cpp` 1 處） |

三個 commit：

1. `eaecdf2c` test：symlink 改成 `#!/bin/sh exec "<絕對路徑>" "$@"` 包裝腳本；路徑比對前 `normpath`。Windows 上 4 個全綠。mutation 1 個（venv 目錄名），紅 3 個；版本錯誤那個測試不看路徑，預期不紅。
2. `0d5f2c3e` fix：新增 `venv_exe`，有 `Scripts/` 就用，否則用 `bin/`；pip 改成 `"$(venv_exe python)" -m pip`。後者是實測出來的：Windows 上 `Scripts/pip.exe install --upgrade pip` exit 1（「To modify pip, please run … python.exe -m pip」），`python -m pip` exit 0。先加 2 個 `Scripts/` 測試，紅 2 個（exit 127，和本機實際失敗相同），修後 6 個全綠。mutation 2 個：固定用 `bin/` 紅 2 個（正好是兩個 Windows 測試）；改回直接呼叫 pip 紅 4 個。
3. `abe86478` chore：版本號全面換成 22。先把測試的版本改成 22，跑紅 6 個，再改 resolver，轉綠。`.clang-format` 的 `SeparateDefinitionBlocks: Leave` 重新量過：改成 `Always` 時，22 在 40 個含 function-try-block 的檔案中有 37 個 `--dry-run --Werror` 紅，`-i` 卻 0 個有變化，和 18 的行為相同，所以維持 `Leave`，只更新註解。[CI-formatter-version-drift] 原地改寫。

## Result

- 本機（Windows 11 ARM64、Python 3.12.10）用空的 `GBM_FORMAT_CACHE_DIR` 跑 `scripts/format.sh`：resolver 自舉 22.1.8 到 `venv-22.1.8/Scripts/`，格式化 199 個檔，只改了上面 2 個；接著 `scripts/format-check.sh` 回報全部乾淨。
- `check-rule-pins.py`、`check-instruction-budget.py` 通過。
- 本機 `scripts/` 的 Python 測試：resolver 6/6 綠。其餘的紅在 `main` 上同樣存在，~~沒有處理~~：`test_format_cpp_hook.py` 14 個 error（WinError 193：`subprocess` 直接執行 `.sh`）——後來由 `9902c908` 處理，見「追加」；`test_check_instruction_budget.py` 2 個 fail，沒有處理。
- CI 的 docker 映像 `ghcr.io/jidicula/clang-format:22` 只指定 major；它實際的 patch 版和 22.1.8 是否一致，看 CI 的結果。

### 已知缺口

- ~~`.claude/hooks/format-cpp.sh` 在 Windows 上不會生效：Claude Code 傳入的 `file_path` 是 `C:\…`，而 `"$root"/src/*` 是 `/c/…`，`case` 永遠不會比對成功。它的測試在 Windows 上也跑不起來（見上）。這兩點使用者還沒裁定，不在本輪範圍內。~~ 使用者裁定修正，見「追加」。原因不只路徑形式，還有 pyenv shim 和 mount。
- ~~resolver 只找 `python3`。只裝了 python.org 版本的 Windows 沒有 `python3`，而 `WindowsApps` 裡同名的 stub 只會開啟 Microsoft Store。本機透過 pyenv-win 的 shim 有 `python3`，所以沒有遇到。~~ 使用者裁定修正，見「追加」。

## 追加：hook 與 resolver 在 Windows 上實際可用

**S**：使用者裁定把上面兩個缺口一起修掉。`arch-suggester` 建議把找 Python 的邏輯放在 `scripts/_find-python.sh` 的 `find_python`，由 hook 和 resolver 各自 source。

**T**：讓 Claude Code 在 Windows 上觸發的 hook 能真的格式化檔案；讓 resolver 在只有 `python` 的機器上也能自舉。

**A**：

1. `9902c908`：hook 的測試改經 `sh` 執行（WinError 193），路徑以磁碟代號開頭時先用 `cygpath -u` 轉換。Windows 上先紅 5 個再綠 9 個；mutation 1 個，紅 5 個。**這個修正不完整**：單元測試全綠，但拿真正的 hook、真正的 payload、對 worktree 裡的 `FsUtil.cpp` 實跑，hook exit 0 卻沒有格式化。
2. 用 `sh -x` 追出兩個原因，都是測試沒有模擬到的環境差異：
   - pyenv-win 的 `python3` shim 底下是 `.bat`，會把 stdin 讀光又不轉交，多行 `-c` 也會壞，所以 hook 讀到的路徑是空字串。直接用真正的 `python3.exe` 讀同一份 payload 就正常。後來又發現，即使只是用 shim 探測直譯器，payload 也會被它吃掉。
   - Git Bash 把 `%TEMP%` 掛在 `/tmp`。`cygpath -u` 把 `C:\…\Temp\…` 轉成 `/tmp/…`，而從 `/c/…` 進入 hook 時，`pwd -P` 得到的是 `/c/…/Temp/…`，兩邊永遠對不上。單元測試的暫存專案是透過 Windows 路徑呼叫 hook，兩邊恰好都是 `/tmp`，所以看不出來。
3. `f2e07f9f`：新增 `find_python`，依序試 `python3`、`python`，用單行 `-c`（stdin 接 `/dev/null`）問出 `sys.executable`，跳過 Store stub 與 Python 2。hook 改用它，並把 `root` 和 `file` 都轉成 `cygpath -m` 的 `C:/…`。新增的測試都先紅後綠：finder 7 個；hook 多一個會吃掉 stdin 的假 shim，以及一個 mount 情境（只在 Windows 上跑）。mutation 3 個、紅 8 個（stdin 2、mount 5、直接呼叫 python3 1）。
4. `8817fd0c`：resolver 改用 `find_python` 建 venv；新增只有 `python` 的情境，先紅後綠；mutation 1 個，紅 1 個。`cq.yml` 加跑 `test_find_python.py`。

**R**：本機實跑通過：真正的 hook、pyenv shim、`C:\` 路徑，把 `FsUtil.cpp` 的 `st {}` 改回 `st{}`；resolver 用空快取跑 `format-check.sh`，199 個檔全部乾淨。本機 `scripts/` 的 Python 測試只剩 `test_check_instruction_budget.py` 的 2 個 fail，`main` 上同樣存在，沒有處理。

教訓：hook 和 resolver 的單元測試把 PATH 和直譯器換成假的，所以測不到 shim 和 mount 這類環境差異。這類腳本的修正，要用真正的輸入跑一次才算數。
