#pragma once

#include "core/graph/GraphSnapshot.h"

#include <string>

namespace gbm {

struct AsciiRenderOptions {
    bool showLaneNumbers = false;
    bool showColors = false;
    bool showShortOid = true;
    std::size_t maxRows = 0;  ///< 0 = all rows.
};

/// Renders a snapshot as deterministic text.
///
/// This exists for testing, and it is the highest-value tooling in the project:
/// the graph is the one component where "it compiles and the unit tests pass" is
/// not enough, because the requirement is visual. Golden text files make layout
/// changes reviewable in a diff, and property tests assert the invariants that
/// the eye would otherwise have to check.
///
/// Output is one line per row, e.g.
///
///     * | 3a4b5c6d  (row 0, lane 0)
///     |\|
///     | * 7e8f9a0b
///     |/
///     * 1c2d3e4f
std::string renderGraphAscii(const GraphSnapshot& snapshot, AsciiRenderOptions options = {});

/// A single row's gutter, without connector rows. Useful in assertions that care
/// about one specific commit.
std::string renderRowAscii(const GraphSnapshot& snapshot, RowId row);

}  // namespace gbm
