#pragma once

#include <cstdint>
#include <optional>
#include <string_view>

namespace gbm {

/// One redraw of git's `--progress` transfer meter, as TASKS' Clone row asks
/// for: 「兩段進度：receiving objects、resolving deltas，各自顯示實際數字」.
/// The percentage is not kept -- it is `current / total`, and git rounds it.
struct TransferProgress {
    enum class Phase { ReceivingObjects, ResolvingDeltas };

    Phase phase = Phase::ReceivingObjects;
    std::uint64_t current = 0;
    std::uint64_t total = 0;

    friend bool operator==(const TransferProgress&, const TransferProgress&) = default;
};

/// The latest transfer state in one chunk of git's stderr, or nothing when the
/// chunk holds no `Receiving objects:` / `Resolving deltas:` line.
///
/// git redraws a line in place with '\r' and ends it with '\n' (or "\r\n"), so
/// one chunk may hold several redraws and both phases; the last one wins.
/// `remote: ...` lines carry the same `(n/m)` shape for the server's own
/// counting and compressing, and are deliberately not matched. Core forces
/// `LC_ALL=C` on every child (`ProcessRunner.cpp`), so the English labels are
/// the only ones git ever prints here.
///
/// Stateless: a line split across two chunks is not reassembled -- its first
/// half has no `(n/m)` yet and yields nothing, and the next chunk's redraw
/// carries the full line again.
std::optional<TransferProgress> parseTransferProgress(std::string_view chunk);

}  // namespace gbm
