import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/list_selection.dart';
import 'repo_identity.dart';

/// The sidebar branch tree's multi-selection, keyed by short branch name.
///
/// A provider rather than `SidebarPanel` local `State`, for two reasons:
/// `WorkspaceScreen._buildActionHandlers()` cannot read a widget's private
/// state, so nothing outside the sidebar could ever act on a selection; and
/// spec page 13's `MULTIBRANCHMENU` needs the same selection visible to the
/// row that was right-clicked, which is a sibling widget.
///
/// Separate from `commitSelectionProvider` on purpose: spec keeps selections
/// from bleeding between lists (「選取狀態跨 scope 不混用」), so the two share
/// [ListSelection]'s transitions without sharing a value.
///
/// **All five selection affordances write this one state.** Spec page 13's
/// `MULTIKEYS` has no checkbox, so the branch row's own gestures are the
/// whole model: a plain click is [ListSelection.single], Ctrl/Cmd-click is
/// [ListSelection.toggle], Shift-click is [ListSelection.range], plus
/// Ctrl/Cmd+A and Shift+arrow from `BranchSelectionShortcuts`. They all go
/// through here rather than growing a second, drifting selection set.
///
/// This comment used to say "the checkbox and Ctrl/Cmd-click"; the checkbox
/// was removed with the `MULTIKEYS` conformance pass and the clicks took
/// over as the primary path.
final StateProviderFamily<ListSelection<String>, RepoIdentity>
branchSelectionProvider =
    StateProvider.family<ListSelection<String>, RepoIdentity>(
      (ref, identity) => const ListSelection<String>(),
    );
