# The current branch has no sorting or filtering privilege in the sidebar — user-ratified

- **Kind**: ruling (user-ratified deviation from spec) · **Pins**: was `REF-head-has-no-sidebar-privilege` · **Code**: `branch_tree_builder.dart`'s `_compareTreeNodes`, `sidebar_panel.dart`'s `_seededExpansionForHead`, `branch_selection_rules.dart`'s `isBulkSelectable`

## Situation
The spec gives HEAD three privileges in the sidebar: ① a filter never drops it (P02-14 rule 7: 「即使不符合條件也不會被濾掉」); ② it sits at the top of its folder (`BRANCH_STATES`: 「永遠置頂於所屬資料夾內，且不受 filter 影響」, and `BRANCH_TREE`'s mock draws `main` above the folders at its own depth); ③ a bold name and a full-row `surfaceSelected` background. All three were implemented and passing.

## Task
The user asked for no head-branch pin and a plain alphabetical tree, with the folders that lead to HEAD expanded by default instead.

## Action
- **The ruling is ① and ② removed, ③ kept.** A pin makes the first row of every level move depending on where HEAD is, and an exempt row makes a filtered sidebar draw a folder with no matching child in it.
- ③ is now the only thing marking HEAD. `isBulkSelectable(ref) => !ref.isHead` depends on it: a permanently selected-looking row that could also be multi-selected would draw two states identically.
- Folders-before-leaves stays, because it is tree *structure*, not branch priority. That is the distinction the user drew.
- 「Where am I」 is answered by seeding `_expandedFolders` with `ancestorFolderPaths(refs.head.branchName)`, on mount and on every checkout, through one `_seededExpansionForHead` gate. It only ever adds, so a folder the user collapsed is never forced open.

## Result
Pinned by these tests:

- `branch_tree_builder_test.dart`: HEAD sorts alphabetically.
- `sidebar_current_branch_no_priority_test.dart`: sort, filter, and the folder that is not drawn.
- `sidebar_filter_test.dart`.
- `sidebar_panel_branch_folder_test.dart`: ancestors expand, a checkout collapses nothing, and a collapsed folder is not forced open.

**Do not reinstate the pin or the filter exemption on the spec's authority.** The citations are still accurate; they no longer decide the behaviour. Evidence: ledger: 側邊欄目前分支不再置頂 (`docs/ledger.md`).
