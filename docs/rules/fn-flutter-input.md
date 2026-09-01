# Flutter: focus, gestures, selection and menus

Pin prefix `FLU-`. Format: [README.md](README.md).

## [FLU-inkwell-tap-gives-no-focus] Tapping an `InkWell` does not give it focus

- **Do**: call `requestFocus()` first if a focus-scoped shortcut has to work after a click.
- **Note**: in the sidebar that call lives in `_onBranchSelect`, so it runs on *every* click.
  The clause that used to be here ("a plain click on a branch row routes through checkout")
  stopped being true when single-click became selection.

## [FLU-hand-rolled-inkwell-hover] A hand-rolled `InkWell` silently inherits `ThemeData.hoverColor`

- **Rule**: about 4% black/white — invisible on a real display.
- **Consequence**: the sidebar shipped with no visible hover for months because its row built
  its own `Container` + `InkWell` instead of using `lib/widgets/gbm_row.dart`, which exists to
  pass `surfaceHover`/`surfaceSelected` for you.
- **Do**: reach for `GbmRow` for anything row-shaped, and **assert the token by identity** —
  hover cannot be proven by a widget test that only checks for no exception.
- **Do**: it recurred twice more in C18, both found by *sweeping every
  `InkWell(`/`GestureDetector(` in the round's changed files* — `FileTreeFolderRow` (folder rows
  had no hover while the file rows around them in the same list did) and a private `_MiniButton`
  in `working_copy_view.dart` that also re-implemented `GbmButton(secondary, sm)`'s border, text
  size and padding by hand. **That grep is worth running at the end of any round that touches
  widgets.**
- **Consequence**: a fourth instance — the sidebar's STASH rows (`sidebar_stash_section.dart`'s
  `_StashRow`, a `GestureDetector` + `Container` with no `InkWell` at all) — shipped with no
  hover, no selected tint, and no discoverable menu trigger, because this one was never swept;
  it took a direct user report rather than the grep above to surface it.
- **Evidence**: ledger: Sidebar branch rows; [ledger: 側邊欄 STASH 列補上
  hover/選取/選單](../ledger/2026-09-01-claude-sidebar-stash-styling-date-3dvzmu.md)

## [FLU-gesture-arena-taxes-double-tap] The gesture arena taxes double-clickable rows, and it is not local

- **Rule**: an `InkWell` holding both `onTap` and `onDoubleTap` withholds the tap for
  `kDoubleTapTimeout` (~300ms), and a `DoubleTapGestureRecognizer` anywhere on the *ancestor*
  path does the same to every child button underneath it — a row's own ⋯ button waits out the
  row's double-tap timer.
- **Do**: put an immediate action on `Listener(onPointerDown:)` (never enters the arena) and keep
  the double-tap on the narrowest subtree that needs it.
- **Note**: `InkResponse` stays hover-enabled with no primary callback at all, because
  `isWidgetEnabled` is `_primaryButtonEnabled || _secondaryButtonEnabled` and `onSecondaryTapDown`
  satisfies the second half.

## [FLU-selectionarea-gives-a-string] `SelectionArea` tells you the selected *string*, not which widgets it covers

- **Rule**: `selection_touch.dart` asks each row's own subtree via a `SelectionListener`.
- **Trap 1**: a row moving between subtrees builds its new listener before the old unmounts (two
  listeners, one notifier, framework assert) — give each row a stable `GlobalKey` so Flutter
  reparents one element.
- **Trap 2**: inserting a widget *among* keyed rows reparents everything below it and perturbs
  the selection.
- **Trap 3**: reacting to every report is a feedback loop (`setState` → geometry moves →
  delegates re-report), so listen only between pointer-down and pointer-up.
- **Do**: **draw nothing derived from that set while the pointer is down** — the one-shot block
  sits inside the scope card, so drawing it mid-drag reparents the rows whose listeners are still
  reporting. The live feedback during a drag is `SelectionArea`'s own text highlight; the block is
  what the drag settles into, so `endGesture()` is what notifies.
- **Note**: all three are 「first frame right, later frames wrong」 — a one-frame assertion cannot
  see any of them.
- **Note**: the honest limit — **no synthetic gesture at either tier reproduces the symptom this
  was reported for** (「只能選一行」). With the gate removed, row-by-row and sub-row device drags
  both stayed green. The invariant is pinned; the cure is not.
- **Do not** read trap 2 as an argument for the one-shot block's fixed slot at the top of the
  column. That **was not the design** — the demo nests it inside the scope card, wrapping the
  selected rows in place, and what makes the nested form safe is the same sentence trap 1 rests
  on: those keys are `GlobalKey`s, so Flutter *moves* the element into its new parent rather than
  rebuilding it. **A recorded hazard is a reason to solve the problem, not a licence to change
  the design.**

## [FLU-clear-selection-before-dispatch] The submit path is a diff-change path, one dispatch later

- **Rule**: `_dropSelection` documented that clearing the highlight is unsafe while the tree
  restructures — and **staging is what restructures it**.
- **Consequence**: a `clearSelection()` deferred to after the dispatch lands inside the
  restructure it caused, and the framework throws `ConcurrentModificationError` out of
  `handleClearSelection`.
- **Do**: clear synchronously **before** dispatching.
- **Note**: nothing below the device tier can see it — the fakes never restage, so the diff never
  changes and the clear always finds a settled tree.

## [FLU-selectableregion-clears-on-focus-loss] `SelectableRegion` clears its selection when it loses focus

- **Rule**: `_handleFocusChanged`, non-web — and it requests focus for itself as a drag begins.
- **Consequence**: an *ancestor* that calls `requestFocus()` on every pointer down is a live way
  to wipe out the selection the gesture is still making.
- **Do**: guard on `!node.hasFocus`. `hasFocus` is true for an ancestor of the primary focus, so
  the guard already covers "the region below me is the one holding it", and key events reach an
  ancestor `CallbackShortcuts` either way.

## [FLU-select-all-in-list-focus-scope] `Ctrl/Cmd+A` must be bound inside the list's own focus scope

- **Rule**: never app-wide — a `Shortcuts` closer to a focused editor than
  `DefaultTextEditingShortcuts` steals text select-all.

## [FLU-menu-enabled-is-visual-only] `GbmMenuItem.enabled: false` is only a visual signal

- **Do**: set `onTap: null` too, or a "disabled" item still fires.
- **Do**: disabled-with-a-tooltip beats hidden — 隱藏會讓人以為功能不存在.

## [FLU-platform-provided-item-forks-an-action] A `PlatformProvidedMenuItem` silently forks one action id into two different windows

- **Rule**: and the dispatch-parity test cannot see it.
- **Consequence**: `helpAbout` was wired in `_buildActionHandlers()` *and* listed in
  `PlatformMenuBarHost._systemProvided`, so Windows/Linux opened `AboutDialogContent` while macOS
  got the native About panel — for months, with every tier green. A system-provided item takes
  **no handler from the map at all**, so «the handler is non-null» was vacuously true, and the
  in-window click test only ever exercised the non-macOS path.
- **Do**: **assert what a menu handler renders, not that it exists** — `item.onSelected!()` then a
  finder on the route's content (`workspace_about_dialog_test.dart`), with a second dialog route
  present as a decoy so a mis-wire fails on content rather than on a missing route.
- **Rule**: spec page 01 is what is being enforced — only the menu bar's *position* follows the
  OS; every window's *contents* are Flutter's on all three platforms.
- **Note**: `PlatformMenuBar` replaces menus from index 1 only, so `MainMenu.xib`'s
  `systemMenu="apple"` menu survives untouched. macOS already has a native About/Quit/Hide there,
  which is what makes a second one under Help redundant rather than required. Quit stays
  system-provided for exactly that reason.

## [FLU-macos-app-name-from-bundle] macOS reads the *application* name from the bundle, never from `NSWindow.title`

- **Rule**: `MainMenu.xib` writes the Apple menu, About, Hide and Quit items as the literal
  placeholder `APP_NAME`, which AppKit resolves from `CFBundleDisplayName` → `CFBundleName` at
  load time; the Dock tooltip and Force-Quit list read the same.
- **Consequence**: it said `gbm_flutter` because `CFBundleName` was `$(PRODUCT_NAME)`, and
  `PRODUCT_NAME` is also the built artifact's name, which `release.yml` hardcodes as
  `gbm_flutter.app` in four places.
- **Do**: writing the literal into `Info.plist` decouples the two (#67 candidate fix 1); renaming
  `PRODUCT_NAME` does not, and is a tag-build-only change.
- **Do**: **no Dart tier reads a bundle's Info.plist and PR CI compiles no macOS (#69)**, so
  `test/platform/window_title_test.dart` asserts the plist as source text — and the value it
  asserts must be checked against a real `flutter build macos` at least once per change.

## [FLU-showgbmmenu-modal-barrier] `showGbmMenu` is built on Material's `showMenu`

- **Consequence**: its modal barrier makes a hover-opened flyout unhoverable from its own parent.
- **Do**: submenus open on tap, and the parent is popped *before* the child's action runs (menu
  items routinely push a dialog). **#87**.

## [FLU-widget-hit-test-gotchas] Three hit-test gotchas that cost a click

- **Rule**: `RadioListTile` needs a `Material` ancestor.
- **Rule**: `Container(color:)` builds an opaque hit-test box while `Listener` defaults to
  `deferToChild`.
- **Rule**: `ReorderableDragStartListener` accepts at `kPrecisePointerHitSlop` (**1.0px** for a
  mouse), so a whole-row drag handle loses ordinary clicks.
