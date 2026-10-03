# Repository selection is a sidebar popover; `/` is only the "nothing open" fallback

- **Kind**: history · **Pins**: was `STRUCT-repo-selection` · **Code**: `repo_switcher_popover.dart`, `WelcomeScreen`

## Situation
The spec has no repository-list page: the window *is* a repository (pages 01–03). Before this split, `/` was a repository dashboard that also owned the base-folder quick-add, and Ctrl/Cmd+R opened a modal dialog listing recents.

## Task
Conform to the spec's model of selection.

## Action
The default route is the last-opened repository's workspace; `/` is the fallback for "nothing open yet". Selecting is a popover under a button at the top of the sidebar (spec page 02 item 15, Ctrl/Cmd+R, `features/repo_switcher/repo_switcher_popover.dart`) — searchable, recents first, `Open` / `Clone` pinned at the bottom, Esc closes without switching, right-click on a row is context menu 05-A. Configuring *where* repositories are discovered (base folders, scan depth, the manually-opened list) is Preferences → Repository sources (spec page 11). `WelcomeScreen` embeds the same `RepoSwitcherList`, because with no repository open there is no sidebar to hang a popover off.

## Result
The dashboard and the recents dialog are gone; `route_paths.dart`'s doc comment states the fallback.
