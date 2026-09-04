import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repo_identity.dart';

/// One open Compare tab's selection state (spec page 12). `right` null
/// means the right side is "Working Copy" -- a UI-level choice, not a ref
/// string, since gbm_capi has a genuinely different call for it
/// (gbm_request_compare_with_working_copy vs gbm_request_compare_refs; see
/// CompareOps.cpp's empty-ref rejection and DiffService::commitVsWorkingTree's
/// doc comment). Immutable, like [WorkspaceTab] -- a new list is always a
/// fresh rebuild, never an in-place mutation (docs/ARCHITECTURE.md
/// invariant 2).
///
/// [scrollOffset] is stored here rather than left to Flutter's own
/// PageStorage mechanism because Compare tabs are plain GoRouter routes
/// (`context.go`), not an always-mounted IndexedStack -- navigating to a
/// different tab disposes the outgoing page.
///
/// **The stronger form of that reason was wrong and is corrected here**
/// ([CULT-correct-the-record]): it used to say 「anything not persisted
/// outside the widget tree would reset to zero」, which reads as
/// 「PageStorage cannot work for a tab」. It can — the management panels do
/// exactly that, by putting the bucket on `WorkspaceScreen`, which is the
/// ShellRoute's shell and therefore *is* outside the disposed subtree. What
/// survives of the reason is the narrower claim: a per-route bucket dies
/// with its route, so the bucket has to be hoisted deliberately. This field
/// remains the right choice here because it is also what `restore` reads on
/// a tab reopened from the spec, which a bucket keyed on a fresh tab id
/// would not carry.
@immutable
class CompareTabSpec {
  const CompareTabSpec({
    required this.id,
    required this.left,
    this.right,
    this.threeDot = true,
    this.scrollOffset = 0.0,
  });

  final String id;
  final String left;
  final String? right;
  final bool threeDot;
  final double scrollOffset;

  bool get rightIsWorkingCopy => right == null;

  CompareTabSpec copyWith({
    String? left,
    String? right,
    bool clearRight = false,
    bool? threeDot,
    double? scrollOffset,
  }) {
    return CompareTabSpec(
      id: id,
      left: left ?? this.left,
      right: clearRight ? null : (right ?? this.right),
      threeDot: threeDot ?? this.threeDot,
      scrollOffset: scrollOffset ?? this.scrollOffset,
    );
  }
}

/// Holds every Compare tab currently open for one repository -- pure UI
/// state, not FFI-backed (unlike [RepoSessionState]), so it lives in its
/// own small family provider rather than growing that class further. Not
/// persisted across app restarts, matching how ephemeral the fixed
/// History/Working Copy tabs' own navigation state already is.
class CompareTabsNotifier extends StateNotifier<List<CompareTabSpec>> {
  CompareTabsNotifier() : super(const <CompareTabSpec>[]);

  int _nextId = 0;

  /// Opens a new tab and returns its id (the caller navigates to
  /// `RoutePaths.compareFor(repoId, id)`).
  String open({required String left, String? right, bool threeDot = true}) {
    final String id = 'compare-${_nextId++}';
    state = <CompareTabSpec>[
      ...state,
      CompareTabSpec(id: id, left: left, right: right, threeDot: threeDot),
    ];
    return id;
  }

  void close(String id) {
    state = state.where((CompareTabSpec tab) => tab.id != id).toList();
  }

  /// Replaces `id`'s ref selection wholesale (both sides change together --
  /// swap needs this, not two separate one-field updates that would each
  /// trigger their own compare request).
  void updateRefs(
    String id, {
    required String left,
    String? right,
    required bool threeDot,
  }) {
    _update(
      id,
      (CompareTabSpec tab) => tab.copyWith(
        left: left,
        right: right,
        clearRight: right == null,
        threeDot: threeDot,
      ),
    );
  }

  void updateScrollOffset(String id, double offset) {
    _update(id, (CompareTabSpec tab) => tab.copyWith(scrollOffset: offset));
  }

  void _update(String id, CompareTabSpec Function(CompareTabSpec) updater) {
    state = <CompareTabSpec>[
      for (final CompareTabSpec tab in state)
        if (tab.id == id) updater(tab) else tab,
    ];
  }
}

final StateNotifierProviderFamily<
  CompareTabsNotifier,
  List<CompareTabSpec>,
  RepoIdentity
>
compareTabsProvider =
    StateNotifierProvider.family<
      CompareTabsNotifier,
      List<CompareTabSpec>,
      RepoIdentity
    >((ref, identity) => CompareTabsNotifier());
