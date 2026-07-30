#include "core/graph/GraphAsciiRenderer.h"

#include <algorithm>
#include <vector>

namespace gbm {

namespace {

/// Two text columns per lane so a connector has somewhere to live.
std::size_t columnOf(LaneId lane) {
    return static_cast<std::size_t>(lane) * 2;
}

void ensureWidth(std::string& line, std::size_t width) {
    if (line.size() < width) {
        line.resize(width, ' ');
    }
}

void put(std::string& line, std::size_t column, char c) {
    ensureWidth(line, column + 1);
    line[column] = c;
}

}  // namespace

std::string renderRowAscii(const GraphSnapshot& snapshot, RowId row) {
    if (row >= snapshot.rows.size()) {
        return {};
    }

    // Every edge that passes through this row occupies its lane; the commit
    // itself replaces whatever is at its own lane.
    std::vector<const Edge*> spanning;
    snapshot.edgesInRange(row, row, spanning);

    std::string line;
    for (const Edge* edge : spanning) {
        const RowId end = edge->parentRow == kRowBoundary ? edge->childRow + 1 : edge->parentRow;
        if (edge->childRow < row && row < end) {
            put(line, columnOf(edge->lane), '|');
        }
    }

    const RowMeta& meta = snapshot.rows[row];
    const char node = meta.isMerge() ? 'M' : (meta.isBoundary() ? 'o' : '*');
    put(line, columnOf(meta.lane), node);
    return line;
}

std::string renderGraphAscii(const GraphSnapshot& snapshot, AsciiRenderOptions options) {
    std::string out;
    const std::size_t rowLimit = options.maxRows == 0
                                     ? snapshot.rows.size()
                                     : std::min(options.maxRows, snapshot.rows.size());

    std::vector<const Edge*> spanning;

    for (RowId row = 0; row < rowLimit; ++row) {
        const RowMeta& meta = snapshot.rows[row];

        // --- the commit's own line -----------------------------------------
        snapshot.edgesInRange(row, row, spanning);
        std::string line;
        for (const Edge* edge : spanning) {
            const RowId end =
                edge->parentRow == kRowBoundary ? edge->childRow + 1 : edge->parentRow;
            // A pass-through: this edge neither starts nor ends here.
            if (edge->childRow < row && row < end) {
                put(line, columnOf(edge->lane), '|');
            }
        }
        const char node = meta.isMerge() ? 'M' : (meta.isBoundary() ? 'o' : '*');
        put(line, columnOf(meta.lane), node);

        std::string suffix;
        if (options.showLaneNumbers) {
            suffix += " L" + std::to_string(meta.lane);
        }
        if (options.showColors) {
            suffix += " c" + std::to_string(static_cast<int>(meta.color));
        }
        if (options.showShortOid && row < snapshot.oids.size()) {
            suffix += " " + snapshot.oids[row].shortHex();
        }
        out += line;
        out += suffix;
        out.push_back('\n');

        // --- the connector line below it -----------------------------------
        // Drawn only when something actually changes shape here, so a linear
        // history renders as an unbroken column of '*' with no filler between.
        if (row + 1 >= rowLimit) {
            continue;
        }

        std::string connector;
        bool interesting = false;

        snapshot.edgesInRange(row, static_cast<RowId>(row + 1), spanning);
        for (const Edge* edge : spanning) {
            const RowId end =
                edge->parentRow == kRowBoundary ? edge->childRow + 1 : edge->parentRow;

            if (edge->childRow == row) {
                // Starts here. A lane change means the edge fans out to the right.
                if (edge->lane != edge->childLane) {
                    put(connector, columnOf(edge->childLane) + 1, '\\');
                    interesting = true;
                    for (LaneId lane = static_cast<LaneId>(edge->childLane + 1); lane < edge->lane;
                         ++lane) {
                        put(connector, columnOf(lane), '_');
                    }
                }
                if (end > row + 1 || edge->lane == edge->childLane) {
                    put(connector, columnOf(edge->lane), '|');
                }
                continue;
            }

            if (end == row + 1) {
                // Ends at the next row. A lane change means it bends back left.
                const LaneId targetLane = snapshot.rows[row + 1].lane;
                if (edge->lane != targetLane) {
                    // The bend sits one column left of the descending lane; lane 0
                    // has no column to its left, so it draws in place.
                    const std::size_t column = columnOf(edge->lane);
                    put(connector, column == 0 ? 0 : column - 1, '/');
                    interesting = true;
                } else {
                    put(connector, columnOf(edge->lane), '|');
                }
                continue;
            }

            put(connector, columnOf(edge->lane), '|');
        }

        if (interesting) {
            out += connector;
            out.push_back('\n');
        }
    }

    if (snapshot.truncated) {
        out += "... (truncated)\n";
    }
    if (snapshot.overflowedEdges > 0) {
        out +=
            "... (" + std::to_string(snapshot.overflowedEdges) + " edges in the overflow lane)\n";
    }
    return out;
}

}  // namespace gbm
