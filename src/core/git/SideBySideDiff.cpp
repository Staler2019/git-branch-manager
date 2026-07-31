#include "core/git/SideBySideDiff.h"

#include <algorithm>

namespace gbm {

std::vector<SideBySideRow> pairHunkForSideBySide(const DiffHunk& hunk) {
    std::vector<SideBySideRow> rows;
    std::vector<const DiffLine*> removedRun;
    std::vector<const DiffLine*> addedRun;

    auto flushRun = [&]() {
        const std::size_t n = std::max(removedRun.size(), addedRun.size());
        for (std::size_t i = 0; i < n; ++i) {
            SideBySideRow row;
            row.left = i < removedRun.size() ? removedRun[i] : nullptr;
            row.right = i < addedRun.size() ? addedRun[i] : nullptr;
            rows.push_back(row);
        }
        removedRun.clear();
        addedRun.clear();
    };

    DiffLineKind lastRealKind = DiffLineKind::Context;
    for (const DiffLine& line : hunk.lines) {
        switch (line.kind) {
            case DiffLineKind::Removed:
                removedRun.push_back(&line);
                lastRealKind = DiffLineKind::Removed;
                break;
            case DiffLineKind::Added:
                addedRun.push_back(&line);
                lastRealKind = DiffLineKind::Added;
                break;
            case DiffLineKind::Context:
                flushRun();
                rows.push_back({&line, &line});
                lastRealKind = DiffLineKind::Context;
                break;
            case DiffLineKind::NoNewlineMarker:
                // Belongs to whichever side it immediately follows, not to both:
                // it means that one file (old or new) has no trailing newline,
                // not that the pair of them agree on it.
                if (lastRealKind == DiffLineKind::Removed) {
                    removedRun.push_back(&line);
                } else if (lastRealKind == DiffLineKind::Added) {
                    addedRun.push_back(&line);
                } else {
                    flushRun();
                    rows.push_back({&line, &line});
                }
                break;
        }
    }
    flushRun();
    return rows;
}

}  // namespace gbm
