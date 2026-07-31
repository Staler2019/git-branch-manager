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
