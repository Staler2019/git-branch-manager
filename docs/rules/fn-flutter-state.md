# Flutter: frames, Riverpod and provider reads

Pin prefix `FLU-`. Format: [README.md](README.md).

## [FLU-postframe-no-frame] `addPostFrameCallback` does not ask for a frame

- **Rule**: it registers a callback for the end of the *next* frame, and if nothing else
  schedules one the callback simply never runs.
- **Consequence**: a drag hides this — the drag itself keeps frames coming — so a
  notification coalesced onto a post-frame callback can work for months and then not arrive
  at all the first time a plain click drives it (`selection_touch.dart`'s `_scheduleNotify`;
  the scope a hunk-heading click had already recorded stayed invisible).
- **Consequence**: in a widget test the gap is total rather than intermittent, because
  `tester.pump()` runs a frame only `if (hasScheduledFrame)` — six pumps in a row did nothing.
- **Do**: pair every deferred notification with `SchedulerBinding.instance.ensureVisualUpdate()`.

## [FLU-no-ref-in-dispose] `ref` inside a `ConsumerState.dispose()` always throws

- **Rule**: `_assertNotDisposed()` gates every `ref` member on `context.mounted`, and the
  element is already unmounted by then.
- **Do**: capture the notifier in `initState()` into a field and guard on `StateNotifier.mounted`.

## [FLU-never-write-provider-in-build] Never write a provider from `build()`

- **Rule**: Riverpod's guard is `assert`-wrapped, so debug crashes but **release strips it and
  lets the write land mid-frame**.
- **Do**: defer to a post-frame callback and recompute from then-current state, not from a
  captured list.

## [FLU-watch-a-record-not-the-state] An unfiltered `ref.watch` of the session rebuilds the whole shell

- **Rule**: `ref.watch(repoSessionProvider(identity))` rebuilds on *every* state publish,
  including caches nothing on screen reads.
- **Consequence**: scrolling History prefetches commit metadata per scroll tick, so each reply
  republished state and rebuilt `MenuBarRow`, `PlatformMenuBarHost`, `ActionToolbar`, `TabRow`
  and `_buildActionHandlers()`. On macOS that rebuilds a real native menu bar; the reported
  symptom was 「每次捲動 menubar 都會閃爍」.
- **Do**: `WorkspaceScreen` watches a **record of the nine fields it consumes** and `read`s the
  full state — it is passed whole to ~40 sites, which `grep 'session\.'` undercounts, because
  bare `session` arguments do not match.
- **Do not** put a derived getter that builds a new collection into such a record.
  `gonePendingRefs` returns a fresh `Set` and a `Set` has no value equality, so including it
  makes the record unequal every time and **silently restores the storm it was meant to remove**.
- **Evidence**: ledger: History 捲動卡頓

## [FLU-listen-misses-the-current-value] `ref.listen` never fires for the value already present when it registers

- **Rule**: every `ref.listen`-driven piece of session state needs something else covering the
  value that was already there — a filter query surviving a repository close is the recorded case.
- **Do**: the test that sees it is the one that seeds the provider *before* pumping.
- **Consequence**: **the mirror case is that a seeded test is blind to the opposite defect.** A
  surface that reads a provider once per *mount* instead of once per *build* answers correctly
  on its only build, so `ref.watch` → `ref.read` stays green across every test that
  seeds-then-pumps. Only flipping the notifier while the tree is on screen tells the two apart —
  verified by exactly that mutation going red in
  `test/integration/soft_wrap_preference_flow_test.dart` and green in the four seeded wrap
  tests next door.
- **Evidence**: ledger: soft warp round

## [FLU-resting-state-replays-stale] An entry point gated on one resting state replays stale answers forever

- **Rule**: once the machine has terminal states. The update dialog checked on mount only from
  `idle`, but `upToDate` / `failed` / `developmentBuild` are terminal — nothing returns them to
  `idle` — so re-opening it re-showed the previous answer for the rest of the session.
- **Do**: gate on a *named predicate* over the whole enum (`UpdateState.wantsFreshCheck`) rather
  than on one value, and check whether every state the machine can rest in has a way out.
- **Note**: the partition is rarely two-way. A **standing offer** the user has not acted on is
  neither stale nor in-flight, and refreshing it costs an API call on the commonest path.
- **Do**: where a `ref.listen` fills the remaining gap, key it on the specific *transition*,
  never on "arrived at X" — `idle` is also where `dismiss()` lands, and re-checking there
  re-offers the very thing the user just declined.
- **Evidence**: ledger: 更新流程的三個缺陷
