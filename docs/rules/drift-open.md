# Current known drift, and open issues

Pin prefix `DRIFT-`. Format: [README.md](README.md).

`gh issue list` is authoritative for issue state; entries here and in the ledger are
historical the moment they are written.

## [DRIFT-context-menu-catalog] The context-menu catalog has no importer

- **Rule**: `features/context_menus/gbm_context_menus.dart` declares all 11 of spec page
  05's groups and is the parity test's acceptance baseline, but no file under `lib/`
  imports it — each render site hand-writes its list.
- **Consequence**: the catalog itself can drift from the spec, which the per-render-site
  audit method cannot detect (**#71**).
- **Do**: all 11 groups are checked against the catalog with no `skip`. Eight are pure
  `*_menu_items.dart` functions — that extraction is the template to follow; 05-A, 05-C
  and 05-K keep private render-site builders for reasons in their matrix rows.

## [DRIFT-05c-is-remote-only] 05-C applies to a remote-only row only

- **Rule**: a *local* branch whose upstream is gone is **05-B**, not 05-C.
- **Consequence**: the code dispatched on `_gone` and got this backwards for rounds,
  leaving a branch that still exists on disk with no Checkout, Merge or Delete.
- **Note**: 05-C is a **user-ratified deviation** from the catalog now, not a drift —
  `Prune this ref` is deleted and `Delete on remote…` is `Delete remote branch…`, both
  recorded in the catalog file's own doc comment.

## [DRIFT-absent-for-no-capi] Absent for lack of a capi entry point

- **Rule**: per-object transfer counts for fetch/pull/push, `git init` / clone, removing a
  *scanned* repository from the switcher, squashing N commits, per-remote Pull/Push, and
  seven `PANELSPEC` detail fields (待提交數, 最後 fetch, 預期 commit, 大小, 剩餘步數,
  自訂測試指令, 欄位選擇器).
- **Evidence**: all tracked on **#76**.

## [DRIFT-auto-fetch-unwired] Preferences → General 的 AUTOMATIC FETCH 整段沒有實作在後面

- **Rule**: `autoFetchEnabled` and `autoFetchMinutes` are stored, drawn and **read by
  nothing** — no timer anywhere issues that fetch.
- **Consequence**: P11 item 9's 「預設每 10 分鐘一次…切換 repo 時重置計時」 has no
  implementation to check against.
- **Note**: two of #102's three `autoFetch*` orphans. The third, `autoFetchPrune`, was
  **deleted** rather than wired — see [GIT-fetch-auto-prunes]. An earlier record put this
  row in Preferences → **Git**; it is `_GeneralSection`.

## [DRIFT-lfs-match-approximate] `lfs_pattern_match.dart` is an approximation

- **Rule**: it approximates gitattributes matching; it is not a port of `wildmatch()`.
- **Consequence**: a pattern it cannot parse matches nothing, so a group reads 0 rather
  than a wrong number.

## [DRIFT-no-pull-dialog] No pull dialog route exists

- **Rule**: P17's 「選單的 Pull… 或 Alt + 點工具列才開」 has nothing to open.
- **Consequence**: `ActionToolbar`'s Pull only runs `pullChanges()` with the configured
  default (**#109**).

## [DRIFT-updater-windows-untested] The updater script's Windows half is text-asserted only

- **Rule**: the `sh` half is genuinely *executed* by `update_installer_script_test.dart`;
  PowerShell cannot be, and PR CI compiles no Windows at all (**#69**).
- **Consequence**: the real install-and-restart has no automated coverage on any platform —
  the device-tier test deliberately stops at `readyToInstall`.
- **Do**: read `<systemTemp>/gbm-update.log` (`updateLogPath()`) — every arm of both
  scripts writes its exit code there, and every failure path reached after the app has
  exited relaunches, so the next failure is diagnosable rather than a vanished window.
- **Evidence**: ledger: 更新流程的三個缺陷

## [DRIFT-open-issues] Open issues

- **Open**: **#62** (TabRow overflow menu), **#68**–**#71**, **#76**, **#84**–**#89**
  (Tier 6 spec blockers), **#92**–**#95** (capi with no spec entry point), **#99**,
  **#101**, **#102**, **#109**, **#119** (side-by-side pins neither gutter — awaiting a
  real-hardware check by the user).
- **Closed**: **#74** (fix/branch-prune-and-gone-marking — its text was corrected first,
  the same function had two further defects the issue never mentioned, per
  [CULT-correct-the-record]); **#75** (all four 260820 `REVISIONS` shortcut gaps landed in
  feat/p03-working-copy-redesign); **#67** (macOS `CFBundleName` is the literal
  `git-branch-manager`, candidate fix 1, in fix/macos-about-dialog-parity).
