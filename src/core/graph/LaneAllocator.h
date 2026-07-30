#pragma once

#include "core/base/ObjectId.h"
#include "core/graph/GraphSnapshot.h"

#include <array>
#include <cstdint>

namespace gbm {

/// Allocates graph columns.
///
/// Two distinct allocation policies, and the difference between them is what
/// produces Fork's layout rather than a generic tangle:
///
///  * `allocateLeftmost()` is used only for ref tips. Because the walk is seeded
///    with HEAD and the trunk branch first, the trunk takes lane 0 and keeps it.
///  * `allocateAfter()` is used for a merge's second and later parents, and
///    guarantees they land strictly to the *right* of the merge commit. A plain
///    lowest-free-lane policy would happily drop a feature branch into lane 0,
///    to the left of trunk, which is exactly the wrong look.
///
/// Occupancy is a 64-bit mask, so both queries are a single count-trailing-zeros
/// on a shifted word.
class LaneAllocator {
public:
    /// Shared column for edges past the rendered lane cap. Never freed, and any
    /// number of edges may occupy it simultaneously.
    static constexpr LaneId kOverflowLane = kMaxLanes;

    static bool isOverflow(LaneId lane) noexcept { return lane >= kMaxLanes; }

    LaneId allocateLeftmost() {
        const LaneId lane = lowestFreeAtOrAfter(0);
        if (isOverflow(lane)) {
            return kOverflowLane;
        }
        markUsed(lane);
        return lane;
    }

    /// Lowest free lane strictly greater than `after`.
    LaneId allocateAfter(LaneId after) {
        if (isOverflow(after)) {
            return kOverflowLane;
        }
        const LaneId lane = lowestFreeAtOrAfter(static_cast<LaneId>(after + 1));
        if (isOverflow(lane)) {
            return kOverflowLane;
        }
        markUsed(lane);
        return lane;
    }

    void release(LaneId lane) {
        if (isOverflow(lane)) {
            return;
        }
        used_ &= ~(1ULL << lane);
    }

    bool inUse(LaneId lane) const noexcept {
        return !isOverflow(lane) && (used_ & (1ULL << lane)) != 0;
    }

    /// Colour is keyed to the object id that *seeded* the lane, never to the lane
    /// index. That is what makes a branch keep its colour across a refresh, an
    /// incremental append, or reuse of a freed lane index — and what makes the
    /// golden tests deterministic. Lane 0 is always the trunk colour.
    void seed(LaneId lane, const ObjectId& oid) {
        if (isOverflow(lane)) {
            return;
        }
        seeds_[lane] = oid;
        colors_[lane] = colorForSeed(lane, oid);
    }

    std::uint8_t colorOf(LaneId lane) const { return isOverflow(lane) ? 0 : colors_[lane]; }

    const ObjectId& seedOf(LaneId lane) const {
        static const ObjectId kNull;
        return isOverflow(lane) ? kNull : seeds_[lane];
    }

    LaneId highWater() const noexcept { return highWater_; }

    static std::uint8_t colorForSeed(LaneId lane, const ObjectId& oid) {
        if (lane == 0) {
            return 0;  // Trunk keeps a fixed, distinct colour.
        }
        return static_cast<std::uint8_t>(1 + (oid.hash() % (kPaletteSize - 1)));
    }

private:
    LaneId lowestFreeAtOrAfter(LaneId start) const {
        if (start >= kMaxLanes) {
            return kOverflowLane;
        }
        const std::uint64_t mask = ~used_ & (~0ULL << start);
        if (mask == 0) {
            return kOverflowLane;
        }
        const auto index = static_cast<LaneId>(countTrailingZeros(mask));
        return index >= kMaxLanes ? kOverflowLane : index;
    }

    void markUsed(LaneId lane) {
        used_ |= (1ULL << lane);
        if (lane + 1 > highWater_) {
            highWater_ = static_cast<LaneId>(lane + 1);
        }
    }

    static int countTrailingZeros(std::uint64_t value) {
#if defined(__GNUC__) || defined(__clang__)
        return __builtin_ctzll(value);
#else
        int count = 0;
        while ((value & 1ULL) == 0) {
            value >>= 1;
            ++count;
        }
        return count;
#endif
    }

    static_assert(kMaxLanes <= 64, "Lane occupancy is a single 64-bit mask");

    std::uint64_t used_ = 0;
    LaneId highWater_ = 0;
    std::array<ObjectId, kMaxLanes> seeds_{};
    std::array<std::uint8_t, kMaxLanes> colors_{};
};

}  // namespace gbm
