---
paths:
  - ".github/**"
  - "CMakeLists.txt"
  - "**/CMakeLists.txt"
  - "CMakePresets.json"
  - ".gitattributes"
  - "app_flutter/scripts/**"
  - "app_flutter/pubspec.yaml"
  - "app_flutter/analysis_options.yaml"
  - "app_flutter/windows/**"
  - "app_flutter/macos/**"
  - "app_flutter/linux/**"
  - ".pre-commit-config.yaml"
  - ".clang-format"
  - "scripts/**"
---

# Toolchain, CI and platform

Pin prefix `CI-`. Format: [README.md](../../docs/rules/README.md).

## [CI-dart-sdk-floor] Dart ≥ 3.13.0

- **Rule**: ~~`app_flutter/pubspec.yaml` pins `sdk: ^3.12.2`; Flutter 3.44.x ships it.~~ **Corrected
  in place (#151)**: `sdk: ^3.13.0`; Flutter 3.47.4 ships Dart 3.13.3.
- **Do**: ~~match `.github/workflows/ci.yml` and `.claude/hooks/session-start.sh`, both on 3.44.9.~~
  four pins move together — `ci.yml`, `cq.yml`, `release.yml` and `.claude/hooks/session-start.sh`,
  all on 3.47.4. The floor sets the language version `dart format` styles by, so raising it
  reformats the tree; do it in the same round as the pin.
- **Evidence**: [ledger: flutter-upgrade](../../docs/ledger/2026-10-04-flutter-upgrade.md)

## [CI-analyze-zero] `flutter analyze` must stay at zero issues

- **Rule**: CI runs it with no tolerance flags.
- **Consequence**: it exits non-zero on *info*-level lints too, so an info lint is a red build.

## [CI-two-workflows] The build job and the format checks are separate workflows

- **Rule**: `ci.yml` builds and tests; `cq.yml` holds the two pure static checks,
  `dart format --set-exit-if-changed .` and `clang-format`.
- **Consequence**: a format failure surfaces on its own check instead of aborting the build.
- **Consequence**: ~~the Flutter UI job sits behind `needs: capi-build`, so it does not run
  at all while any capi job is red — a green capi run can surface Flutter problems that
  were previously invisible rather than absent.~~ **Corrected in place (#151 round)**: the
  `needs` is gone — `flutter-ci` read nothing `capi-build` produced, so it only queued the
  Flutter jobs behind Windows capi's ~9–10 minutes. Both groups now run in parallel, and a red
  capi no longer hides a Flutter failure. Do not re-add it without a real artifact handoff.
- **Evidence**: [ledger: flutter-upgrade](../../docs/ledger/2026-10-04-flutter-upgrade.md)

## [CI-formatter-version-drift] Both formatters drift by version, in both directions

- **Rule**: `dart format`'s output is not stable across Dart SDKs, ~~and
  `subosito/flutter-action@v2`'s `channel: stable` floats with no SDK pinned~~ — every
  flutter-action use is pinned now (`cq.yml` lints it), so a flap needs a local SDK that differs
  from the pin: one file then moves between two valid formattings (#151: worktrees_panel_test.dart
  under 3.47.4 vs CI's 3.44.9). `clang-format` is pinned to v18 in `cq.yml` and
  `.pre-commit-config.yaml`; a local v22 reformats lines v18 left alone.
- **Do**: never run either wholesale **on a local version that differs from CI's pin**. Restore the
  file, re-apply only the intended edit, and check the new lines survive byte-for-byte. With
  `flutter --version` equal to the pin, `dart format .` is safe.
- **Do**: check `.clang-format` first — a suggestion coming from the repo's own config
  (e.g. `SeparateDefinitionBlocks: Always`, an option since v14) applies to CI's v18 too
  and is safe to take.
- **Evidence**: ledger: Known gaps; [ledger: flutter-upgrade](../../docs/ledger/2026-10-04-flutter-upgrade.md)

## [CI-linux-only] ~~PR CI compiles Linux only~~ — superseded: `flutter-ci` is a three-OS matrix

- **Rule (superseded)**: ~~`flutter build linux --debug` is the only compile. `windows/runner/`
  and `macos/Runner/` are built by nothing until a release tag.~~ ~~Assume any edit there
  reaches `main` uncompiled (**#69**).~~
- **Rule**: `ci.yml`'s `flutter-ci` job is a `fail-fast: false` matrix over
  `ubuntu-22.04` / `macos-26` / `windows-latest`, each running `flutter analyze`,
  `flutter test`, the Phase A capi build (`build_capi.sh`, or `build_capi.ps1` on
  Windows) and `flutter build <target> --debug`. So `windows/runner/` and
  `macos/Runner/` are compiled on every PR now, not only at a release tag.
- **Rule**: **what survives is the reason `test/platform/window_title_test.dart` exists** —
  it asserts those runner sources as *strings*, which catches a drifting literal and never
  a compile error. The matrix supplies the compile; that test still supplies the literal.
- **Rule**: the Windows job carries `ilammy/msvc-dev-cmd@v1` for the reason
  [CI-windows-toolchain-not-implied] gives — without it CMake's probe may take the image's
  MinGW `g++` and the job compiles something nobody ships.
- **Note**: **the C++ tier was never Linux-only** — `capi-build` has run the three-OS matrix
  all along. This rule only ever described the *Flutter* job, and that is the half now closed.
- **Note**: **still not covered**: `integration_test/` ([TEST-device-tier-not-in-ci]) and the
  PowerShell updater's *behaviour* ([DRIFT-updater-windows-untested]) — the matrix compiles and
  unit-tests the three platforms, it does not run the device tier on any of them.
- **Evidence**: [ledger: Windows 與 macOS 的 Flutter CI](../../docs/ledger/2026-09-28-chore-accept-toolchain-bump.md)

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

## [CI-byte-compared-fixture-needs-notext] A fixture compared as **bytes** must be `-text` in `.gitattributes`, or it fails on Windows only

- **Rule**: Git for Windows ships `core.autocrlf=true` in its **system** config, so a checkout
  on a Windows runner rewrites every LF in a file git considers text to CRLF *in the working
  tree*. The blob is untouched, so nothing in the repository looks wrong and no other platform
  can see it.
- **Consequence**: `update_script_golden_test.dart` compares the generated updater against
  `test/fixtures/gbm-update.ps1.golden` **as bytes** — deliberately, because the BOM is half of
  what it pins ([CI-ps1-needs-bom]) and a string comparison would normalise it away — while
  `UpdateInstaller` always emits `\n`. On Windows the golden on disk had CRLF and the generated
  script had LF, so the comparison failed at the **first newline**: `at location [77] is <10>
  instead of <13>`. 2966 passed, 1 failed.
- **Rule**: **this was invisible for as long as the golden existed.** The Flutter job was
  ubuntu-only ([CI-linux-only]), and `cq.yml`'s `powershell-parse` job does read this file on a
  real `windows-latest` — but PowerShell does not care about CRLF, so that job was green
  throughout. It took the three-OS matrix's *first run* to surface it.
- **Do**: `*.golden -text`, scoped to the class rather than the one path. A `.golden` exists to
  be compared byte-for-byte, so eol conversion is wrong for every one of them. Verify with
  `git ls-files --eol <path>` — it must print `attr/-text`, not an empty `attr/`.
- **Do not** reach for `binary`: that is `-text -diff`, and this golden is a reviewable
  PowerShell script whose diff is worth reading.
- **Note**: no re-normalisation was needed — the blob was already LF (`git show HEAD:<path> |
  tr -dc '\r' | wc -c` → 0), so the attribute alone fixes the checkout. A fixture already
  stored with CRLF would need `git add --renormalize` as well.
- **Do**: the root cause was **reproduced locally before the fix**, not inferred from the
  platform: piping the blob through `.replace(b'\n', b'\r\n')` puts byte 77 at 13 against the
  blob's 10, which is the assertion's two numbers exactly.
- **See also**: `GitIntegrationTest.cpp`'s `DiscardsSelectedLinesOfAnUntrackedFile` comment is the same `core.autocrlf` biting
  one layer down — there it is git rewriting a *work-tree file an operation wrote*, here it is
  git rewriting a *checked-in fixture on checkout*.
- **Evidence**: [ledger: Windows 與 macOS 的 Flutter CI](../../docs/ledger/2026-09-28-chore-accept-toolchain-bump.md)

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
- **Evidence**: [ledger: Install and restart 卡在 Installing…](../../docs/ledger/2026-09-01-claude-windows-app-update-install-irloo0.md)

## [CI-no-ctest-timeout] `enable_testing()` without `include(CTest)` means there is **no** per-test timeout at all

- **Rule**: the documented 1500-second default is the **CTest module's** `DART_TESTING_TIMEOUT`,
  written into `DartConfiguration.tcl` — and the root `CMakeLists.txt` calls `enable_testing()`
  only, so that file is never generated and ctest applies no deadline of any kind. The two
  `gtest_discover_tests` calls set `DISCOVERY_TIMEOUT`, which bounds *discovery*, not a test.
- **Consequence**: a test that fails **by hanging** runs to GitHub's 6-hour job cap. Measured:
  one Windows `capi (FFI)` job sat 81 minutes on a single test against a 9–11 minute baseline,
  and stopped only because a human cancelled it — which is also the only way its log became
  readable, since GitHub refuses to serve logs for an in-progress job.
- **Consequence**: it costs more than the one job. `flutter-ci` was then `needs: capi-build`
  ([CI-two-workflows], since removed), so it did not run **once** on that branch while a Windows job could not
  finish.
- **Do**: both layers, because they answer different questions. `tbase.execution.timeout` in
  `CMakePresets.json` names the culprit (`***Timeout`, with the test's name, and the remaining
  tests still run under `stopOnFailure: false`); `timeout-minutes` on every `ci.yml` job caps
  the bill. A job-level timeout **cancels** the job, and `if: failure()` does not fire on a
  cancellation — so the `Upload test logs` step is unreachable by that path and only the ctest
  timeout leaves evidence behind.
- **Do**: put it on `tbase`, not on `gtest_discover_tests(PROPERTIES TIMEOUT n)`. All five test
  presets inherit `tbase`, including any added later; the gtest form covers only the two gtest
  executables and misses every `add_test()` fixture test. An explicit `TIMEOUT` property still
  wins over `--timeout`, so `graph_matches_git_on_generated_history` and
  `commit_graph_speedup_ratio` keep their `TIMEOUT 600` untouched.
- **Do not** reach for `include(CTest)` to get the default back: it pulls in `BUILD_TESTING`
  (which then fights `GBM_BUILD_TESTS`) and the CDash submit targets, and 1500 seconds is far
  too long to be the instrument here.
- **Evidence**: [ledger: 追加，Windows CI 卡 81 分鐘](../../docs/ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [CI-windows-toolchain-not-implied] `runs-on: windows-*` names an operating system, not a compiler — CMake picks one off `PATH`

- **Rule**: the GitHub Windows images ship **both** MSVC and a MinGW `g++` on `PATH`, and with no
  toolchain step CMake's compiler probe takes whichever it finds first. `ci.yml`'s capi job gets
  MSVC only because it runs `ilammy/msvc-dev-cmd@v1`; a new Windows job that omits that step is
  not "the same as the others", it is a different toolchain.
- **Consequence**: for a *measurement* job this is worse than a red build. The subject of
  `windows_job_object_spawn_cost` is the per-spawn cost of a Win32 job object **in the shipped
  binary**; a number taken under a different CRT and a different C++ runtime measures something
  nobody runs, and it arrives as a perfectly plausible microsecond figure with nothing anywhere
  saying it is wrong.
- **Consequence**: it was caught only by luck — the MinGW build failed on a latent missing
  `<cstring>` in `FsUtil.cpp` that MSVC tolerates through transitive includes. Without that
  coincidence the round would have published a fabricated number into
  `docs/reports/windows-process-cost.md`, the document that exists to record the *previous*
  fabricated number.
- **Do**: before trusting any new performance job, establish that it builds **the thing you
  ship** — read the compiler path out of the build log (`C:\mingw64\bin\c++.exe` vs `cl.exe`)
  rather than inferring it from `runs-on`. This is [CPP-windows-terminate-hangs-join]'s control-group
  lesson moved one step earlier: prove you are measuring the right thing before arguing about
  how precisely you measured it.
- **Evidence**: [ledger: 追加五](../../docs/ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [CI-ctest-hides-passing-output] `ctest --output-on-failure` publishes nothing from a test that passes

- **Rule**: a measurement written to stdout/stderr by a **passing** test is swallowed unless
  `-V` (or a preset's `output.verbosity: verbose`) is in effect. `--output-on-failure` is, by
  name, the opposite of what a measurement job needs.
- **Consequence**: the failure mode is a **green job that produced no data** — the publish step
  finds no `job-object-ab:` line and reports "the run failed before measuring" on a run where
  nothing failed. That reads as a broken test rather than a missing flag.
- **Rule**: **bypassing a preset forfeits its settings.** `perf-nightly.yml`'s Windows job uses a
  bare `ctest --test-dir … -L perf -R …` rather than `--preset perf`, deliberately (the preset's
  other member builds a 100k-commit fixture), and therefore does not inherit that preset's
  `verbosity: verbose` the way the Linux job does.
- **Do**: any ctest invocation whose *product* is text from a passing test takes `-V`. Where the
  run is filtered out of a preset for cost reasons, re-state every setting that mattered.
- **Evidence**: [ledger: 追加五](../../docs/ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [CI-platform-guarded-block-uncompiled] Code inside `#ifdef _WIN32` is compiled by exactly one CI job, so its errors arrive one per round-trip

- **Rule**: a local `cmake --build --target all` on macOS reports success having never parsed a
  single line inside a `#ifdef _WIN32`. [CI-linux-only] says PR CI compiles Linux only for the
  *Flutter runners*; this is the same hole one level down, inside a file that does build
  everywhere.
- **Consequence**: the compiler stops at the first error, so each fix buys exactly one more error
  and each costs a full CI round-trip. `spawn_cost_win.cpp` shipped a nonexistent header
  (`core/git/ProcessRunner.h`) and a one-argument `IProcessRunner::run()` — the second was
  unreachable until the first was fixed, and neither was visible to a fully green local suite.
- **Do**: after the second round-trip, stop and compile it locally against a stub. A
  signature-only `windows.h` (~50 lines, never linked) plus a wrapper that includes the std
  headers under the *real* platform **before** `#define _WIN32`, then `#include`s the `.cpp`,
  type-checks the whole block with `c++ -fsyntax-only`. Ordering the define after the std
  includes is what keeps libc++ out of the fake platform.
- **Do**: **mutation-check the stub before believing a clean result** — a probe that never
  reaches the guarded block reports exactly the same silence as one that reaches it and finds
  nothing. Mutating a *Win32* call specifically (not just a cross-platform one) is what tells
  the two apart.
- **Note**: MSVC's `/W4 /WX` still catches things a stub cannot, C4774 (a non-literal `printf`
  format string, e.g. from a ternary) among them. The stub narrows the round-trips; it does not
  remove the need for one.
- **Do**: **the probe type-checks the code, and says nothing about the build wiring** — its
  `-I` flags are hand-fed, so they can differ from what the real target actually has. A new
  sibling header (`tools/spawn_cost_verdict.h`) passed the probe under `-I tests` and then
  failed MSVC with `C1083: Cannot open include file`, because `gbm_spawn_cost` links
  `gbm_core` but not `gbm_test_support` — and the latter is what carries `tests/` as a
  PUBLIC include dir. The local build was no help either: the `#include` sits *inside* the
  `#ifdef _WIN32`, so a green macOS build never looked at it.
- **Do**: verify an include path from **`compile_commands.json`**, not from a build that may
  have skipped the guarded block — `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`, then read the `-I`
  list for that one object. It is platform-independent evidence, and deleting the
  `target_include_directories` line makes `tests/` vanish from it, which is the mutation that
  proves the line is load-bearing rather than decorative.
- **Evidence**: [ledger: 追加五](../../docs/ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [CI-newer-flutter-dirties-tracked-files] A Flutter SDK newer than CI's pin rewrites two tracked files

- **Rule**: ~~with 3.47.5 against CI's 3.44.9, `flutter pub get` re-resolves `pubspec.lock`
  (matcher, meta, test_api, vector_math) and prepends an `analyzer: exclude:` block to
  `app_flutter/analysis_options.yaml` («Upgrading analysis_options.yaml to exclude build and
  platform directories»). A later `flutter test` put the second back after it had been reverted.~~
  **Corrected in place (#151)**: both files already carry the 3.47 resolution (accepted by
  chore/accept-toolchain-bump), and CI now pins 3.47.4 — `flutter pub get` on 3.47.4 left both
  clean. The rule holds only for a local SDK that differs from the pin.
- **Consequence**: `git status` shows both as modified after any local run, and a `git add -A`
  or `git commit -a` ships an SDK-version artefact as part of an unrelated change.
- **Do**: stage by file ([CULT-standing-rules]). Save `git diff` of the two files to the scratchpad
  first and undo with `git apply -R` from that patch — never `git checkout -- <file>`.
- **Evidence**: [ledger: fix/windows-host-updater-tests](../../docs/ledger/2026-09-19-fix-windows-host-updater-tests.md); [ledger: flutter-upgrade](../../docs/ledger/2026-10-04-flutter-upgrade.md)
