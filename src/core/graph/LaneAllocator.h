#pragma once

#include "core/base/ObjectId.h"
#include "core/graph/GraphSnapshot.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>

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
    /// index — that is what survives reuse of a freed lane index and keeps a
    /// rebuild deterministic — and then adjusted, but only when the hash's
    /// answer would put this lane within a quarter turn of a lane drawn right
    /// beside it. Lane 0 is always the trunk colour.
    ///
    /// Note what oid-keying does *not* buy, because the comment here used to
    /// claim it: a ref tip's lane is seeded with the **tip commit itself**
    /// (`GraphBuilder.cpp`'s `lanes_.seed(lane, oid)` on the no-incoming-edges
    /// path), so committing on a branch already recoloured it long before the
    /// neighbour rule existed. What is genuinely stable is a lane whose seed
    /// does not move and whose neighbours do not crowd it.
    void seed(LaneId lane, const ObjectId& oid) {
        if (isOverflow(lane)) {
            return;
        }
        seeds_[lane] = oid;
        colors_[lane] = colorForSeed(lane, oid, neighborColor(lane, -1), neighborColor(lane, +1));
    }

    std::uint8_t colorOf(LaneId lane) const { return isOverflow(lane) ? 0 : colors_[lane]; }

    const ObjectId& seedOf(LaneId lane) const {
        static const ObjectId kNull;
        return isOverflow(lane) ? kNull : seeds_[lane];
    }

    LaneId highWater() const noexcept { return highWater_; }

    /// No lane on that side, so nothing to keep clear of.
    static constexpr int kNoNeighbor = -1;

    /// How far apart, in palette steps, a new lane is kept from each of the two
    /// lanes drawn beside it.
    ///
    /// **3 of 12 steps is a quarter turn of the colour wheel**, and that is a
    /// real statement about colour only because the UI's palette is generated
    /// at even 30-degree OkLCH steps *in index order*
    /// (`app_flutter/lib/theme/tokens.dart`'s `graphLanes`, pinned by
    /// `gbm_lane_palette_test.dart`). This class never sees an RGB value; the
    /// ordering contract is the whole reason index arithmetic can stand in for
    /// hue distance. Reorder that list and this code keeps running, quietly
    /// spreading nothing.
    static constexpr int kMinColorSeparation = 3;

    /// Circular distance between two palette indices, i.e. their hue distance
    /// divided by 30 degrees.
    static int colorDistance(std::uint8_t a, std::uint8_t b) {
        const int d = std::abs(static_cast<int>(a) - static_cast<int>(b));
        return std::min(d, static_cast<int>(kPaletteSize) - d);
    }

    /// The palette index for a lane seeded by `oid`, given the colours of the
    /// lanes immediately left and right of it (`kNoNeighbor` where there is
    /// none).
    ///
    /// The hash decides outright whenever it can, and only a crowded answer is
    /// repaired — probing outwards `+1, -1, +2, -2, …` from the hash's choice
    /// over the eleven non-trunk indices. That ordering matters: it lands on
    /// the nearest acceptable colour rather than an arbitrary one, so the
    /// choice still tracks the seed oid and a lane that stops being crowded
    /// returns to the colour it wanted.
    ///
    /// The eleven probes cover every non-trunk index, and the loop always
    /// returns from inside: each of the two neighbours forbids the five
    /// indices within two steps of its own, so at most ten of the twelve are
    /// ruled out and at least one of the eleven candidates survives. The
    /// trailing `return` is therefore unreachable today — it is a `return`
    /// rather than an assert so that widening the constraint later degrades to
    /// the plain hash instead of trapping.
    static std::uint8_t colorForSeed(LaneId lane,
                                     const ObjectId& oid,
                                     int leftColor,
                                     int rightColor) {
        if (lane == 0) {
            return 0;  // Trunk keeps a fixed, distinct colour.
        }
        constexpr int kChoices = static_cast<int>(kPaletteSize) - 1;
        const auto base = static_cast<std::uint8_t>(1 + (oid.hash() % kChoices));

        for (int step = 0; step < kChoices; ++step) {
            const int offset = (step % 2 == 0) ? step / 2 : -((step + 1) / 2);
            const int index = (static_cast<int>(base) - 1 + offset + kChoices * 2) % kChoices;
            const auto candidate = static_cast<std::uint8_t>(1 + index);
            if (isClearOf(candidate, leftColor) && isClearOf(candidate, rightColor)) {
                return candidate;
            }
        }
        return base;
    }

private:
    static bool isClearOf(std::uint8_t candidate, int neighbor) {
        return neighbor == kNoNeighbor ||
               colorDistance(candidate, static_cast<std::uint8_t>(neighbor)) >= kMinColorSeparation;
    }

    /// The colour of the lane `delta` columns away, or [kNoNeighbor] if there
    /// is no such lane or nothing is currently drawn in it. A lane not in
    /// `used_` is not on screen, so its stale colour must not constrain
    /// anything — otherwise a long-closed branch would go on pushing live ones
    /// around.
    int neighborColor(LaneId lane, int delta) const {
        const int index = static_cast<int>(lane) + delta;
        if (index < 0 || index >= static_cast<int>(kMaxLanes)) {
            return kNoNeighbor;
        }
        const auto neighbor = static_cast<LaneId>(index);
        return inUse(neighbor) ? static_cast<int>(colors_[neighbor]) : kNoNeighbor;
    }

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
