# Toolchain, CI and platform

Pin prefix `CI-`. Format: [README.md](README.md).

## [CI-dart-sdk-floor] Dart ≥ 3.12.2

- **Rule**: `app_flutter/pubspec.yaml` pins `sdk: ^3.12.2`; Flutter 3.44.x ships it.
- **Do**: match `.github/workflows/ci.yml` and `.claude/hooks/session-start.sh`, both on 3.44.9.

## [CI-analyze-zero] `flutter analyze` must stay at zero issues

- **Rule**: CI runs it with no tolerance flags.
- **Consequence**: it exits non-zero on *info*-level lints too, so an info lint is a red build.

## [CI-two-workflows] The build job and the format checks are separate workflows

- **Rule**: `ci.yml` builds and tests; `cq.yml` holds the two pure static checks,
  `dart format --set-exit-if-changed .` and `clang-format`.
- **Consequence**: a format failure surfaces on its own check instead of aborting the build.
- **Consequence**: the Flutter UI job sits behind `needs: capi-build`, so it does not run
  at all while any capi job is red — a green capi run can surface Flutter problems that
  were previously invisible rather than absent.

## [CI-formatter-version-drift] Both formatters drift by version, in both directions

- **Rule**: `dart format`'s output is not stable across Dart SDKs, and
  `subosito/flutter-action@v2`'s `channel: stable` floats with no SDK pinned — so one file
  can flap between two valid formattings. `clang-format` is pinned to v18 in `cq.yml` and
  `.pre-commit-config.yaml`; a local v22 reformats lines v18 left alone.
- **Do**: never run either wholesale. Restore the file, re-apply only the intended edit,
  and check the new lines survive byte-for-byte.
- **Do**: check `.clang-format` first — a suggestion coming from the repo's own config
  (e.g. `SeparateDefinitionBlocks: Always`, an option since v14) applies to CI's v18 too
  and is safe to take.
- **Evidence**: ledger: Known gaps

## [CI-linux-only] PR CI compiles Linux only

- **Rule**: `flutter build linux --debug` is the only compile. `windows/runner/` and
  `macos/Runner/` are built by nothing until a release tag.
- **Consequence**: assume any edit there reaches `main` uncompiled (**#69**).
  `test/platform/window_title_test.dart` asserts those runner sources as strings, which
  catches a drifting literal but never a compile error.

## [CI-windows-cwd-lock] Windows refuses to rename or delete any process's CWD

- **Rule**: `Process.start` inherits the parent's CWD when given none, and an app launched
  by double-clicking its `.exe` has the install directory as its CWD — so the detached
  updater stood inside the very folder it then tried to move aside.
- **Consequence**: `Move-Item` lost every retry and the self-install died silently with the
  app already gone. POSIX permits the rename, so macOS and Linux never showed it.
- **Do**: give any detached process that will touch the install tree an explicit
  `workingDirectory` outside it. Inside a PowerShell script `Set-Location` is **not**
  enough — it moves the provider location while the Win32 process directory keeps the
  handle, so `[System.Environment]::CurrentDirectory` has to be assigned too.
- **Evidence**: ledger: 更新流程的三個缺陷

## [CI-ps1-needs-bom] `powershell.exe` reads a BOM-less `.ps1` as ANSI, not UTF-8

- **Rule**: Windows PowerShell 5.1 is what `-File` resolves to on a stock machine, and the
  updater bakes its three paths in as literals.
- **Consequence**: a user name in Chinese mojibaked all three into the same silent failure.
- **Do**: write generated `.ps1` as UTF-8 **with** a BOM. `sh` needs the opposite (a BOM on
  line 1 is a syntax error), so the two generators differ deliberately.
- **Evidence**: ledger: 更新流程的三個缺陷

## [CI-powershell-golden-parse] The generated `.ps1` is syntax-checked on `windows-latest`, from a golden, parse-only

- **Rule**: `cq.yml`'s `powershell-parse` job runs
  `[Management.Automation.Language.Parser]::ParseFile()` over
  `app_flutter/test/fixtures/gbm-update.ps1.golden` under `shell: powershell` — Windows
  PowerShell 5.1, which is what `-File` resolves to on a stock machine ([CI-ps1-needs-bom]).
- **Rule**: **parse only, never execute.** The script renames an install directory aside.
- **Consequence**: a syntax error there happens *before* the script's first statement, so it
  cannot even write its own transcript — the user sees 「app 關掉了然後沒回來」 with no evidence
  at all. Nothing else in the repo compiles, parses or runs this file ([CI-linux-only], **#69**).
- **Do**: the job parses a checked-in golden rather than generating the script, which keeps a
  Flutter toolchain off the Windows runner. Drift is closed by
  `update_script_golden_test.dart`: change the generator without regenerating → red on Linux;
  regenerate → a syntax error is carried into the golden verbatim → the Windows job catches it.
  **A lazily regenerated golden is not a hole; carrying the mistake forward is what makes the
  third step work.**
- **Do**: regenerate with `GBM_UPDATE_GOLDEN=1 flutter test test/data/services/update_script_golden_test.dart`.
  The golden is compared as **bytes**, because the BOM is half of what it pins.
- **Evidence**: [ledger: Install and restart 卡在 Installing…](../ledger/2026-09-01-claude-windows-app-update-install-irloo0.md)
