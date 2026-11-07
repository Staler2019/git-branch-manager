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
- 本機 `scripts/` 的 Python 測試：resolver 6/6 綠。其餘的紅在 `main` 上同樣存在，沒有處理：`test_format_cpp_hook.py` 14 個 error（WinError 193：`subprocess` 直接執行 `.sh`）；`test_check_instruction_budget.py` 2 個 fail。
- CI 的 docker 映像 `ghcr.io/jidicula/clang-format:22` 只指定 major；它實際的 patch 版和 22.1.8 是否一致，看 CI 的結果。

### 已知缺口

- `.claude/hooks/format-cpp.sh` 在 Windows 上不會生效：Claude Code 傳入的 `file_path` 是 `C:\…`，而 `"$root"/src/*` 是 `/c/…`，`case` 永遠不會比對成功。它的測試在 Windows 上也跑不起來（見上）。這兩點使用者還沒裁定，不在本輪範圍內。
- resolver 只找 `python3`。只裝了 python.org 版本的 Windows 沒有 `python3`，而 `WindowsApps` 裡同名的 stub 只會開啟 Microsoft Store。本機透過 pyenv-win 的 shim 有 `python3`，所以沒有遇到。
