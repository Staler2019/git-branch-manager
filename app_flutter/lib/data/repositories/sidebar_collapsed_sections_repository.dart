import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repo_identity.dart';

/// The sidebar sections that can be collapsed from their header.
enum SidebarSection { tags, stash }

/// Which of the sidebar's TAGS / STASH sections the user has collapsed, per
/// repository. Empty -- everything open -- is the default.
///
/// Same shape as `branchFilterQueryProvider`, for the same reasons: a
/// provider rather than `SidebarPanel` State because the sidebar is hideable
/// and the choice must outlive it (spec P02's folder rule, 「收合狀態記憶在該
/// repo」, which ruling 2026-10-18 extends to these two sections); not
/// persisted and not autoDispose, so it lasts the run and no longer.
///
/// This is the *remembered* choice only. While the filter has a query both
/// sections are drawn open regardless (P02-14), and this set is left alone
/// so clearing the query brings the collapsed state back. Writers replace
/// the set rather than mutating it.
final StateProviderFamily<Set<SidebarSection>, RepoIdentity>
sidebarCollapsedSectionsProvider =
    StateProvider.family<Set<SidebarSection>, RepoIdentity>(
      (ref, identity) => const <SidebarSection>{},
    );
