import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repo_identity.dart';

/// The sidebar's one filter box (spec P02 item 14), which filters Branches,
/// Tags and Stashes together.
///
/// A provider rather than `SidebarPanel` local `State` because the History
/// graph converges on this value: narrowing to exactly one branch collapses
/// the graph to a single line (see `graph_filter_convergence.dart`). Local
/// state dies with the widget, and the sidebar is hideable — so hiding it
/// would leave the graph converged with the filter that caused it no longer
/// visible and no longer clearable, which is exactly the `material_state_hidden`
/// shape this project's UX rubric flags.
///
/// Not persisted, unlike `chromeVisibilityProvider`: a filter is something the
/// user is doing now, not a setting. Reopening a repository shows all of it.
final StateProviderFamily<String, RepoIdentity> branchFilterQueryProvider =
    StateProvider.family<String, RepoIdentity>((ref, identity) => '');
