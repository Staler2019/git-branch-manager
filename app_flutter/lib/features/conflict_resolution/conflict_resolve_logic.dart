import '../../data/models/parsed_conflict_file.dart';
import '../../data/models/working_copy_status.dart';

/// Mirrors `gbm::ConflictRegionChoice` (src/core/git/ConflictMarkerParser.h).
/// `custom` (per-line composition) is part of the core enum's shape for
/// forward compatibility but is never produced here -- see
/// conflict_resolve_window.dart's doc comment on the reduced scope of this
/// port (whole-region take-ours/take-theirs/edit-manually, not core's
/// drag-and-drop/per-line click composition).
enum ConflictRegionChoice { unresolved, ours, theirs, custom }

/// Dart port of `ConflictMarkerParser::assemble` (src/core/git/
/// ConflictMarkerParser.cpp) -- pure concatenation of already-fetched,
/// already-parsed segment data (see parsed_conflict_file.dart), not a
/// reimplementation of the marker *parsing* itself (that stays server-side,
/// exposed via gbm_parse_conflict_markers -- see this file's sibling
/// gbm_request_working_tree_content()/gbm_parse_conflict_markers() doc
/// comments in gbm_capi.h for why: marker recognition has real edge-case
/// behavior -- diff3 base handling, a malformed-marker fallback, exact
/// line-ending preservation -- that belongs in core, not duplicated here).
/// Returns null if `resolutions.length != parsed.regionCount`, or any entry
/// is still [ConflictRegionChoice.unresolved] -- callers gate "Save" on
/// every region having a choice.
String? assembleConflictResolution(
  ParsedConflictFile parsed,
  List<ConflictRegionChoice> resolutions,
) {
  if (resolutions.length != parsed.regionCount) return null;
  if (resolutions.any((r) => r == ConflictRegionChoice.unresolved)) return null;

  final StringBuffer output = StringBuffer();
  int regionIndex = 0;
  for (final ConflictSegment segment in parsed.segments) {
    if (segment.kind == ConflictSegmentKind.text) {
      for (final String line in segment.lines) {
        output.write(line);
      }
      continue;
    }

    final ConflictRegionChoice resolution = resolutions[regionIndex++];
    final List<String> chosen = switch (resolution) {
      ConflictRegionChoice.ours => segment.ours,
      ConflictRegionChoice.theirs => segment.theirs,
      ConflictRegionChoice.custom => const <String>[],
      ConflictRegionChoice.unresolved => const <String>[],
    };
    for (final String line in chosen) {
      output.write(line);
    }
  }
  return output.toString();
}

/// Whether a batch-tracked path is still stuck in conflict or has been
/// resolved -- by this window, or externally (a plain `git add` run in a
/// terminal alongside it). [ConflictBatch.merge] can't tell the two apart
/// and doesn't need to.
enum ConflictFileState { unresolved, resolved }

class ConflictBatchEntry {
  const ConflictBatchEntry({required this.path, required this.state});

  final String path;
  final ConflictFileState state;

  ConflictBatchEntry copyWith({ConflictFileState? state}) =>
      ConflictBatchEntry(path: path, state: state ?? this.state);
}

/// Dart port of `gbm::ConflictBatch` (src/core/git/ConflictBatch.h) -- pure
/// UI-state bookkeeping (list reconciliation against repeated
/// [WorkingCopyStatus] scans) with no git operations of its own, so this
/// stays client-side rather than round-tripping through capi for what is
/// session-local presentation state. Tracks every conflicted path seen
/// across the lifetime of one merge/rebase/cherry-pick -- a *union* of every
/// status scan, not a snapshot of any single one -- so a just-resolved file
/// stays visible with a checkmark instead of vanishing the instant it drops
/// out of [WorkingCopyStatus.conflicted]. In-memory only, scoped to this
/// window's lifetime -- unlike the Qt original's `ConflictBatchStore`
/// (QSettings-backed persistence across app restarts), which is a
/// deliberately separate scope reduction here (see conflict_resolve_window.dart).
class ConflictBatch {
  ConflictBatch() : _entries = <ConflictBatchEntry>[];

  final List<ConflictBatchEntry> _entries;

  List<ConflictBatchEntry> get entries =>
      List<ConflictBatchEntry>.unmodifiable(_entries);

  /// Merges in one working-copy-status scan's conflicted paths: every
  /// already-tracked path has its state re-derived fresh from whether it's
  /// still present in `conflicted` (present -> unresolved, absent ->
  /// resolved -- never "sticky"), and any new path is appended in
  /// first-appearance order.
  void merge(List<WorkingCopyEntry> conflicted) {
    final Set<String> stillConflicted = conflicted.map((e) => e.path).toSet();
    for (int i = 0; i < _entries.length; i++) {
      final ConflictBatchEntry entry = _entries[i];
      _entries[i] = entry.copyWith(
        state: stillConflicted.contains(entry.path)
            ? ConflictFileState.unresolved
            : ConflictFileState.resolved,
      );
    }

    final Set<String> alreadyTracked = _entries.map((e) => e.path).toSet();
    for (final WorkingCopyEntry candidate in conflicted) {
      if (alreadyTracked.contains(candidate.path)) continue;
      _entries.add(
        ConflictBatchEntry(
          path: candidate.path,
          state: ConflictFileState.unresolved,
        ),
      );
      alreadyTracked.add(candidate.path);
    }
  }

  int get resolvedCount =>
      _entries.where((e) => e.state == ConflictFileState.resolved).length;

  bool get allResolved =>
      _entries.isNotEmpty && resolvedCount == _entries.length;
}
