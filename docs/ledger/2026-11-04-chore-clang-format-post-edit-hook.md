# chore/clang-format-post-edit-hook — agent 編輯 C++ 後自動格式化

## Situation

`dart format` 已有全域 PostToolUse hook，C++ 沒有對應機制。本機 `clang-format` 是 23.1.5，CI 鎖 18，`pre-commit` 沒安裝，`.git/hooks` 也沒有啟用的 hook，所以格式錯誤要到 `cq.yml` 才會發現。

## Task

使用者裁定做兩項：專案層的 C++ post-edit 格式化，以及全域的 guard hook。guard 在 `~/.claude`（`feat/guard-repo-discipline`），不屬於這個 repo，這裡只記錄 C++ 這一半。

## Action

- 新增 `.claude/hooks/format-cpp.sh`：範圍與 CI 相同（`src/` 底下的 `.cpp`、`.h`），一次一個檔，版本由 `_resolve-clang-format.sh` 決定。
- 實跑時發現既有 bug：`~/.cache/gbm-clang-format/venv-18.1.8` 指向已移除的 pyenv 3.13.12，`bin/clang-format` 存在但無法啟動。解析器只檢查 `-x`，於是不重建，直接回報 `not major version 18`，`format.sh`、`format-check.sh` 同樣無法使用。
- 解析器改為實際詢問版本，不符就 `venv --clear` 重建。
- hook 失敗時 exit 2，而不是照原本建議的 exit 0。上面的 bug 就是靠這個才看得到。
- 兩份測試都用假的工具，接進 `cq.yml`，不依賴機器上有沒有 clang-format。

## Result

- `test_resolve_clang_format.py` 4 項、`test_format_cpp_hook.py` 9 項通過。
- mutation：解析器 mutations-run=2、tests-reddened=1、1；hook mutations-run=12、mutations-killed=11。首輪另有 `$file` 未加引號存活，假 formatter 改成逐一框住引數後抓到；剩下 1 條是等價 mutant（無路徑時輸出 `x`，一樣不符合 `case` 而 exit 0）。
- 實機：重建 venv 花 12 秒；`format-check.sh` 回報 196 個檔案全部乾淨。
- 實機：Write 一個格式不良的 `src/` 檔案後被格式化為 v18 輸出。註冊後第一次 Write 沒有觸發，第二次才觸發，同一批送出的工具呼叫可能還沒載入新設定。
- 沒跑 ctest 與 Flutter 測試，這輪沒有動到 C++ 或 Dart 產品程式碼。
