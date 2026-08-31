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

    /// Marks a lane occupied without handing it to anybody.
    ///
    /// This is how GraphBuilder holds lane 0 for HEAD's branch tip: with the bit
    /// set, `lowestFreeAtOrAfter()` skips the lane, so `allocateLeftmost()` and
    /// `allocateAfter()` both start looking one column further right until the
    /// reserving commit arrives and takes it. No separate mask is needed for
    /// this -- "reserved" and "occupied" are the same question as far as
    /// allocation is concerned, and the *identity* of the reserver is
    /// GraphBuilder's business, not this class's.
    ///
    /// A reserved lane is never released by accident: `release()` is only called
    /// for a lane some edge is descending in, and no edge can descend in a lane
    /// no row has occupied yet.
    void reserve(LaneId lane) {
        if (isOverflow(lane)) {
            return;
        }
        markUsed(lane);
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
    /// answer would crowd a lane drawn near it. Lane 0 is always the trunk
    /// colour.
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
        colors_[lane] = colorForSeed(lane, oid, sideColors(lane, -1), sideColors(lane, +1));
    }

    std::uint8_t colorOf(LaneId lane) const { return isOverflow(lane) ? 0 : colors_[lane]; }

    const ObjectId& seedOf(LaneId lane) const {
        static const ObjectId kNull;
        return isOverflow(lane) ? kNull : seeds_[lane];
    }

    LaneId highWater() const noexcept { return highWater_; }

    /// No lane on that side, so nothing to keep clear of.
    static constexpr int kNoNeighbor = -1;

    /// How many columns either side of a new lane are allowed to constrain its
    /// colour.
    ///
    /// It was 1, and 1 left the gap a user photographed: two branches in the
    /// same colour with exactly one lane between them. Nothing checked the
    /// column two away, on either side.
    ///
    /// The ref-tip path was thinner still. `allocateLeftmost` returns the
    /// *lowest free* lane, so a tip is seeded with every lane to its left
    /// occupied and every lane to its right free by construction -- on that
    /// path "both neighbours" could only ever mean the left one. It is
    /// `allocateAfter`, for a merge's second and later parents, that seeds
    /// lanes with something already drawn to the right, and that half was
    /// live: deleting the right-hand check reddens
    /// `InvariantAdjacentColumnsNeverLookAlikeAtAnyRow`, which is how this
    /// paragraph got its second sentence.
    static constexpr int kNeighborWindow = 5;

    /// How far apart, in palette steps, a new lane is kept from a lane drawn
    /// directly beside it.
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

    /// The separation a lane `columns` away asks for, in palette steps: a
    /// quarter turn from the column beside it, 60 degrees from the one after
    /// that, and merely *not the same colour* out to [kNeighborWindow].
    ///
    /// The profile decays because closeness is what makes a repeat read as one
    /// branch rather than two: at the shipped lane pitch of 11 the three tiers
    /// are 11px, 22px and 33-55px apart. Past the window the palette simply
    /// runs out -- there are eleven non-trunk colours and up to `kMaxLanes`
    /// (48) columns, so a wide enough graph must repeat somewhere and the only
    /// question is where.
    static constexpr int requiredSeparation(int columns) {
        if (columns == 1) {
            return kMinColorSeparation;
        }
        if (columns == 2) {
            return 2;
        }
        return columns <= kNeighborWindow ? 1 : 0;
    }

    /// What one step of shortfall against a lane `columns` away costs.
    ///
    /// These are a lexicographic order written as a sum, and the arithmetic is
    /// what makes that true: everything below offset 1 can contribute at most
    /// `2 x 10 x 2 + 6 x 1 x 1 = 46`, so a single step of improvement against
    /// an immediate neighbour (100) outranks any combination of the rest. A
    /// candidate is therefore never allowed to crowd the lane beside it in
    /// order to please four distant ones.
    static constexpr int penaltyWeight(int columns) {
        if (columns == 1) {
            return 100;
        }
        return columns == 2 ? 10 : 1;
    }

    /// Circular distance between two palette indices, i.e. their hue distance
    /// divided by 30 degrees.
    static int colorDistance(std::uint8_t a, std::uint8_t b) {
        const int d = std::abs(static_cast<int>(a) - static_cast<int>(b));
        return std::min(d, static_cast<int>(kPaletteSize) - d);
    }

    /// The colours of the lanes within [kNeighborWindow] columns on one side,
    /// nearest first: `[0]` is one column away, `[1]` two, and so on.
    /// [kNoNeighbor] wherever that lane is not currently drawn.
    using SideColors = std::array<int, kNeighborWindow>;

    /// The palette index for a lane seeded by `oid`, given what is drawn to
    /// its left and right.
    ///
    /// The hash decides outright whenever it can: probing outwards
    /// `+1, -1, +2, -2, …` from `1 + hash % 11`, the first candidate that
    /// crowds nothing wins, so an uncrowded lane keeps exactly the colour its
    /// seed oid asked for and a lane that stops being crowded returns to it.
    ///
    /// Only when no candidate is clear does the scoring matter, and then the
    /// least-crowded one wins rather than an arbitrary fallback. That is the
    /// whole reason this is a minimisation and not a filter: with a five-wide
    /// window the constraints can genuinely be unsatisfiable (eleven candidates
    /// against ten neighbours), and degrading to "as far apart as this palette
    /// allows" is the right answer where "far enough apart" has none.
    static std::uint8_t colorForSeed(LaneId lane,
                                     const ObjectId& oid,
                                     const SideColors& left,
                                     const SideColors& right) {
        if (lane == 0) {
            return 0;  // Trunk keeps a fixed, distinct colour.
        }
        constexpr int kChoices = static_cast<int>(kPaletteSize) - 1;
        const auto base = static_cast<std::uint8_t>(1 + (oid.hash() % kChoices));

        std::uint8_t best = base;
        int bestPenalty = -1;
        for (int step = 0; step < kChoices; ++step) {
            const int offset = (step % 2 == 0) ? step / 2 : -((step + 1) / 2);
            const int index = (static_cast<int>(base) - 1 + offset + kChoices * 2) % kChoices;
            const auto candidate = static_cast<std::uint8_t>(1 + index);
            const int penalty = crowdingOf(candidate, left, right);
            if (penalty == 0) {
                return candidate;
            }
            if (bestPenalty < 0 || penalty < bestPenalty) {
                bestPenalty = penalty;
                best = candidate;
            }
        }
        return best;
    }

private:
    /// Weighted shortfall of `candidate` against everything in the window, 0
    /// when every lane in it is far enough away.
    static int crowdingOf(std::uint8_t candidate, const SideColors& left, const SideColors& right) {
        int total = 0;
        for (int i = 0; i < kNeighborWindow; ++i) {
            const auto slot = static_cast<std::size_t>(i);
            total += shortfall(candidate, left[slot], i + 1);
            total += shortfall(candidate, right[slot], i + 1);
        }
        return total;
    }

    static int shortfall(std::uint8_t candidate, int neighbor, int columns) {
        if (neighbor == kNoNeighbor) {
            return 0;
        }
        const int missing = requiredSeparation(columns) -
                            colorDistance(candidate, static_cast<std::uint8_t>(neighbor));
        return missing <= 0 ? 0 : missing * penaltyWeight(columns);
    }

    /// The window on one side of `lane`: `direction` is -1 for left, +1 for
    /// right.
    SideColors sideColors(LaneId lane, int direction) const {
        SideColors colors{};
        for (int i = 0; i < kNeighborWindow; ++i) {
            colors[static_cast<std::size_t>(i)] = neighborColor(lane, direction * (i + 1));
        }
        return colors;
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
