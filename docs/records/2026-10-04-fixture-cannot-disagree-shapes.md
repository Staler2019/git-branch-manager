# Fifteen fixtures that could not disagree with the code

- **Kind**: history · **Pins**: `TEST-fixture-cannot-disagree` (the pin and its 1–15 numbering stay in `.claude/rules/arch-testing.md`; about 100 code comments cite a row by number) · **Code**: tests across `app_flutter/test/**`, `tests/**`

## Situation
Across rounds, fifteen tests passed identically before and after a real fix. Each was a different *shape* of the same failure: the fixture or the assertion could not disagree with the code.

## Task
Keep every recorded case so a future test author can match a new defect against a known shape, while the always-loaded rule stays short.

## Action
The table and the per-shape reasoning below were moved verbatim from `.claude/rules/arch-testing.md` on 2026-10-04 (before that, the heading said "Twelve recorded shapes" while the table already held fifteen).

| # | Shape | Recorded case | Why it stayed green |
|---|---|---|---|
| 1 | *derives* one field from another | `hasTrackingInfo: upstream.isNotEmpty` (Tier 0c) | the fixture computes what the code computes |
| 2 | *borrowed* from a test whose subject contradicts yours | `_mergeState()`'s `isSequencerOperation` (cancel-surface round) | the borrowed state asserts the opposite case |
| 3 | *cannot express* the case | a single shared `GraphRow` instance (graph-edge round) | two rows are the same object |
| 4 | *cannot shrink* | a `repoRefsProvider` override pinned to one snapshot | no selected branch can ever vanish |
| 5 | two subjects *indistinguishable to the assertion* | `ActionToolbar`'s Branch and Stash share a gate and both only `context.push(...)`, so `onPressed != null` stayed green with the handlers swapped (P02-2) | sentinel `dialogRoute`s are what told them apart |
| 6 | *content contradicts its own name* | a "same-size edit must be re-read" test wrote 8 bytes then 7 (C18) | size really had changed, so dropping mtime from the key stayed green |
| 7 | *premise a later decision revoked* | 05-G's device fixture put two insertions one line apart; 變體 B then merged anything ≤ 2 unchanged lines apart (C18) | the same bytes silently became *one* scope |
| 8 | the **assertion**, not the fixture, is too weak | «controls are to the right of the status text» is true under `WrapAlignment.spaceBetween` **and** `start` (conflict-banner round) | «controls' right edge equals the Wrap's right edge» is the same claim stated tightly enough to fail |
| 9 | **cross-language**: hand-sets a field production never sets | every Dart test wrote `isSymbolic: true` by hand while `RefStore` never assigned it | **both languages stay green at once** — the C++ struct member did exist and was serialized |
| 10 | *varies more than the subject*, so an unrelated path answers correctly | History's uncommitted-row fixture rebuilt its `GraphSnapshotView` on every call, so emitting a clean working copy also handed `repoGraphProvider` a new object (discard round) | the rebuild that repaints the row came from the graph, not the working copy — mutating the row's `ref.watch` to `ref.read` left the file **fully green** |
| 11 | *cannot express* the failing condition at this tier at all | `.timeout()` around a synchronously-blocking `_closeSessions()` (Windows update round) | no fake-async widget test blocks a real event loop, so an empty fix goes green — see `update_watchdog.dart`'s `updateWatchdogEntryPoint` |
| 12 | the **environment** gains a permanent item, quietly widening an exact count | D7 seeded a pinned Worktrees tab, and `expect(tabs, hasLength(1))` had meant 「this menu item opened exactly one tab」 | the seed alone satisfies the count, so the assertion now passes for a menu item that opens **nothing** |
| 13 | the fixture supplies **bounded ambient constraints by construction**, and the defect only fires under unbounded ones | `GbmDialogWarnField`'s own widget test pumped it inside `Scaffold(body: Center(child: ...))` — `Center` hands its child a *bounded* constraint | a `Row` using `CrossAxisAlignment.stretch` needs an unbounded ambient height to break under (a `Column` hands non-flex children unbounded height; `GbmDialogWarnField` wraps its `Row` in `IntrinsicHeight`); the isolated test could never produce one, so it stayed green until the widget was wired into a real dialog's `Column` |
| 14 | the assertion reads a **proxy for the render tree**, not the render tree itself | Add Worktree's "default path" tests asserted `pathField.controller?.text` — correct, and all three stayed green through the whole round | a `TextField`'s `controller.text` says what the *model* computed; it cannot see `InputDecoration.labelText` painting over the value (a floating label needs room above a fixed-height box, so `gbmInputDecoration()` takes no `labelText`) — the field was never empty, just visually unreadable, and no test asked what actually got painted |
| 15 | the assertion measures the **widget's** box, while the defect is in a box that widget's own render object paints | 位置's field and the `GbmButton` beside it both measured `h=30.0` in a probe, while the real app drew the field's outline at 23 | a `TextField`'s rect is the `SizedBox`'s number; `_RenderDecoration` paints the outline in a **separate child** sized by `isDense` (`gbmInputDecoration()`'s `isDense: false` comment) — so both the widget rect and the shared 30px constant agree with each other and with nothing the user sees |

- **Do**: count the bytes the fixture actually writes, not the bytes the test's name claims (6).
- **Do**: **when a rule about how input is grouped changes, every fixture that encodes a gap,
  a count or an adjacency has to be re-read against the new rule** — nothing else will
  notice (7).
- **Do**: a mutation that comes back green is as often a weak assertion as a missing one (8).
- **Do**: when something becomes **always present**, every exact-count assertion about it turns
  vague. Fix it by *filtering the constant out and re-counting the subject*, never by bumping 1 to
  2 — the bumped number is satisfied by the constant alone (12).
- **Do**: **hold everything but the subject identical across a transition** — hoist the
  untouched halves of a state fixture into shared instances, so the only thing that can
  drive the rebuild is the thing under test (10). Two fixtures pumped separately cannot see
  this at all; it needs one tree and two states.
- **Do**: **ask which object paints the thing you are asserting about**, not which object you named to find it. A finder resolves to a widget; the defect may be one render object below it, and the two report different numbers with no error anywhere (14, 15).
- **Do**: **when a field crosses a language boundary, ask which side assigns it** — a
  hand-set fixture is evidence about the consumer, never about the producer. Neither side can
  see the gap; only the real binary across the boundary can, which is why that test belongs in
  `GitIntegrationTest.cpp` and the FFI-payload one in `SessionApiTest.cpp` (9).


## Result
The L1 rule keeps the fifteen shape names and the generalised Do bullets; this record keeps the cases. When a sixteenth shape is found, append a row here and its name to the rule's list.
