# Device-tier E2E (`integration_test/`)

Complements `test/integration/`'s widget-tier tests (`FakeRepoSessionController`,
see the project root `CLAUDE.md`'s "Testing tiers" section): these run the
real `GbmApp` against the real `gbm_capi` native library and a real
temporary git repository created per test.

## Precondition

The native library must already exist at `app_flutter/build/native/`:

```bash
./scripts/build_capi.sh   # or build_capi.ps1 on Windows
```

`flutter test integration_test/` does not go through either of the
packaged-build paths that would otherwise put it there (see
`lib/data/ffi/native_library.dart`'s doc comment).

## Running

Each file must be run **individually**, not as a directory:

```bash
flutter test integration_test/repo_lifecycle_test.dart -d macos
flutter test integration_test/commit_flow_test.dart -d macos
flutter test integration_test/conflict_flow_test.dart -d macos
```

(`-d linux` / `-d windows` on those platforms.)

`flutter test integration_test/ -d macos` (the whole directory in one
invocation) is unreliable on macOS: every file after the first fails with
`Error waiting for a debug connection: The log reader stopped unexpectedly,
or never started.` -- a `flutter test`/macOS desktop-runner launch-sequencing
issue reproduced consistently across multiple runs during this audit, not a
bug in these tests (each one passes on its own). Revisit this note if a
future Flutter/`flutter_tools` version fixes multi-app-launch sequencing.

## CI

Not wired into `ci.yml` yet -- needs a capi build step on a desktop runner
first, and the one-file-at-a-time constraint above means a CI job would need
to loop over the files rather than invoke the directory once. Track this as
a follow-up; per this audit's plan, it should land as an optional job that
does not block the existing `flutter-ci`/`capi-build` gates.
