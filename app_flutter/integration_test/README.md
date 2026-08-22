# Device-tier E2E (`integration_test/`)

Complements `test/integration/`'s widget-tier tests (`FakeRepoSessionController`,
see the project root `CLAUDE.md`'s "Testing tiers" section): these run the
real `GbmApp` against the real `gbm_capi` native library and a real
temporary git repository created per test.

## Precondition

The native library must be resolvable by `native_library.dart`'s candidate
list. **`app_flutter/scripts/build_capi.sh` does now exist** -- it was added
by `ab58282` (2026-08-13) alongside the macOS Runner's Xcode Run Script
phase. This paragraph used to say the opposite ("no such script was ever
added, so do not go looking for it") and was simply never revisited; it is
corrected here rather than deleted, because the earlier claim is the reason
`native_library.dart`'s doc comment mentioning the script reads as a
dangling reference. Running it builds `--preset capi-only` and copies the
result into candidate #3.

What actually happens on macOS, observed while adding
`multi_push_flow_test.dart`: `flutter test integration_test/<file> -d macos`
builds the Runner target, whose "Build gbm_capi" Xcode Run Script phase runs
`cmake --preset capi-only` and copies the result next to the executable
inside the `.app` -- candidate #2. So the dylib is rebuilt from current
source on every run, and no manual step is needed. Linux and Windows reach
candidate #2 the same way, via their CMake Phase B block.

Candidate #3 (`app_flutter/build/native/`) is the manual escape hatch. If you
put a dylib there by hand, remember it is a **copy**: see the staleness
warning below.

## Running

Each file must be run **individually**, not as a directory:

```bash
flutter test integration_test/repo_lifecycle_test.dart -d macos
flutter test integration_test/commit_flow_test.dart -d macos
flutter test integration_test/conflict_flow_test.dart -d macos
flutter test integration_test/context_menu_flows_test.dart -d macos
flutter test integration_test/rename_branch_flow_test.dart -d macos
flutter test integration_test/multi_push_flow_test.dart -d macos
flutter test integration_test/commit_file_counts_test.dart -d macos
```

(`-d linux` / `-d windows` on those platforms.)

`flutter test integration_test/ -d macos` (the whole directory in one
invocation) is unreliable on macOS: every file after the first fails with
`Error waiting for a debug connection: The log reader stopped unexpectedly,
or never started.` -- a `flutter test`/macOS desktop-runner launch-sequencing
issue reproduced consistently across multiple runs during this audit, not a
bug in these tests (each one passes on its own). Revisit this note if a
future Flutter/`flutter_tools` version fixes multi-app-launch sequencing.

## The native library must be current, not merely present

`build/native/libgbm_capi.dylib` is a **copy**, not a symlink: a stale one
keeps loading happily and the flow under test then fails in a way that looks
exactly like a Dart bug. `context_menu_flows_test.dart`'s discard flow needs
`gbm_discard_lines`, which did not exist in any dylib built before it;
`multi_push_flow_test.dart` needs `gbm_push`'s two-parameter multi-branch
form. If you populated candidate #3 by hand, re-copy it after every capi
change -- the Xcode/CMake build phases feeding candidate #2 do not touch it.

## Shared preferences are the machine's real ones

There is no in-memory backend on a live desktop binding, so these tests read
whatever the developer's own use of the app left behind.
`pumpRealAppOn` therefore seeds `recents.repos` and **clears every
`panelLayout.*` key**: a splitter ratio dragged in the real app persists,
and one was observed making History's Changed files panel overlap the commit
graph by ~28px -- enough that a row's centre sits under the neighbouring
pane and a correct `tester.tap` silently misses its hit test. Any other
preference a future test depends on should be normalised there too, rather
than assumed clean.

## CI

Not wired into `ci.yml` yet -- needs a capi build step on a desktop runner
first, and the one-file-at-a-time constraint above means a CI job would need
to loop over the files rather than invoke the directory once. Track this as
a follow-up; per this audit's plan, it should land as an optional job that
does not block the existing `flutter-ci`/`capi-build` gates.
