import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repo_identity.dart';

/// Immutable snapshot of working copy commit message draft and diff scroll state.
/// Created with default values; updated via [WorkingCopyDraftController] methods.
class WorkingCopyDraft {
  const WorkingCopyDraft({
    this.summary = '',
    this.description = '',
    this.diffScrollOffset = 0.0,
  });

  /// First line of the commit message (typically treated separately by Git).
  final String summary;

  /// Additional commit message body (lines after the first).
  final String description;

  /// Scroll position in the diff pane (in logical pixels), preserved when
  /// switching between history and working-copy tabs.
  final double diffScrollOffset;

  /// Creates a copy with any fields optionally replaced.
  WorkingCopyDraft copyWith({
    String? summary,
    String? description,
    double? diffScrollOffset,
  }) {
    return WorkingCopyDraft(
      summary: summary ?? this.summary,
      description: description ?? this.description,
      diffScrollOffset: diffScrollOffset ?? this.diffScrollOffset,
    );
  }
}

/// State notifier for mutable working copy draft state.
/// Updates are applied via copyWith() -- never in-place mutation.
class WorkingCopyDraftController extends StateNotifier<WorkingCopyDraft> {
  WorkingCopyDraftController() : super(const WorkingCopyDraft());

  /// Updates the commit message summary (first line).
  void updateSummary(String value) {
    state = state.copyWith(summary: value);
  }

  /// Updates the commit message description (body text).
  void updateDescription(String value) {
    state = state.copyWith(description: value);
  }

  /// Updates the diff pane scroll offset (in logical pixels).
  void updateDiffScrollOffset(double value) {
    state = state.copyWith(diffScrollOffset: value);
  }

  /// Resets all fields to their defaults (empty strings, 0.0 offset).
  /// Called after a successful commit.
  void reset() {
    state = const WorkingCopyDraft();
  }
}

/// Provider for per-repository working copy draft state.
///
/// Keyed by [RepoIdentity], so each open repository keeps its own draft
/// independently. The provider is NOT autoDispose -- state must survive the
/// WorkingCopyView widget rebuilding when the user switches between the
/// History and Working Copy tabs. The ShellRoute (features/workspace) stays
/// mounted across that switch and is the provider's implied watcher; only
/// when the entire repo ShellRoute unmounts does the provider dispose.
final workingCopyDraftProvider =
    StateNotifierProvider.family<
      WorkingCopyDraftController,
      WorkingCopyDraft,
      RepoIdentity
    >((ref, identity) => WorkingCopyDraftController());
