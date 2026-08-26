#pragma once

#include "core/git/UnifiedDiffParser.h"

#include <vector>

namespace gbm {

/// One rendered row of a side-by-side diff. Either side may be null, meaning
/// that side is blank padding -- a pure addition has no left line, a pure
/// deletion has no right line.
struct SideBySideRow {
    const DiffLine* left = nullptr;
    const DiffLine* right = nullptr;
};

/// Turns a hunk's flat, unified-diff-ordered line sequence into paired
/// left/right rows for a side-by-side view.
///
/// **Nothing in this codebase calls this function, and that is a decision
/// rather than an oversight.** The surface that needs the pairing is the
/// Flutter side, which already holds a decoded `DiffHunk`; round-tripping
/// through capi for a synchronous relayout of data it has in hand would be
/// pure overhead. So the live implementation is the Dart port at
/// `app_flutter/lib/features/diff/side_by_side_diff.dart`, and this stays as
/// the **reference implementation** it mirrors line for line — the same
/// standing `GraphAsciiRenderer.cpp` has for the commit graph. Deleting it as
/// orphan wiring would take the reference with it.
///
/// The two are kept in lockstep deliberately, test cases included:
/// `tests/unit/SideBySideDiffTest.cpp` and
/// `app_flutter/test/features/diff/side_by_side_diff_test.dart` carry the
/// same eight cases in the same order. **Change one, change both** — most
/// easily got wrong in the `NoNewlineMarker` arm below, whose two cases were
/// added to both suites at once precisely because neither had reached it.
///
/// Git's unified diff already groups each changed region as a contiguous run of
/// removed lines immediately followed by a contiguous run of added lines (a
/// "diff3-style" chunk), bracketed by context. That is exactly the shape a
/// side-by-side view wants: pairing removed[i] with added[i] up to the shorter
/// run's length, and padding the rest with blanks, reproduces what every
/// side-by-side diff tool shows without needing a second alignment pass or any
/// additional data beyond what UnifiedDiffParser already produces. Context
/// lines pass straight across unchanged, appearing identically on both sides.
std::vector<SideBySideRow> pairHunkForSideBySide(const DiffHunk& hunk);

}  // namespace gbm
