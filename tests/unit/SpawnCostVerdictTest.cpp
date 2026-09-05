// The A/B verdict rules, tested where they can actually be contradicted.
//
// `spawn_cost_win.cpp` is Windows-only and runs on one scheduled job, so its
// own execution is not a tier that disagrees with anything -- the interesting
// branch here (a negative delta) needs a *noisy* Windows runner on top of that.
// The classification was split into `tools/spawn_cost_verdict.h` for exactly
// this reason; these cases run everywhere, on every PR.
#include "tools/spawn_cost_verdict.h"

#include <gtest/gtest.h>

namespace {

using gbm::spawncost::classifyVerdict;
using gbm::spawncost::kMinSamplesForVerdict;
using gbm::spawncost::Verdict;

/// Enough samples and a control that came back, so the sample-count and
/// instrument guards are out of the way and the delta is what decides.
constexpr long long kGoodSamples = kMinSamplesForVerdict;
constexpr double kGoodRecovery = 0.03;

TEST(SpawnCostVerdict, ADeltaClearOfTheResolutionIsMeasured) {
    // The real run: +71us against an 18us resolution.
    EXPECT_EQ(classifyVerdict(kGoodSamples, kGoodRecovery, 71, 18), Verdict::Measured);
}

TEST(SpawnCostVerdict, ANegativeDeltaIsNoiseAndNeverAMeasurement) {
    // A job object cannot make spawning faster. Before this was a signed
    // comparison, `llabs(-50) > 18` fell through to `measured` and published
    // `job_overhead_us=-50 overhead_fraction_of_git=-0.002` -- an impossible
    // number, promoted unattended, and passing any `fraction <= gate` check
    // because a negative is below every threshold.
    EXPECT_EQ(classifyVerdict(kGoodSamples, kGoodRecovery, -50, 18), Verdict::BelowNoise);

    // Magnitude does not rescue it: a *bigger* negative is stronger evidence
    // that the resolution is understated, not weaker.
    EXPECT_EQ(classifyVerdict(kGoodSamples, kGoodRecovery, -5000, 18), Verdict::BelowNoise);
}

TEST(SpawnCostVerdict, ADeltaAtOrUnderTheResolutionIsBelowNoise) {
    EXPECT_EQ(classifyVerdict(kGoodSamples, kGoodRecovery, 17, 18), Verdict::BelowNoise);
    // Equal is not resolved -- the resolution is the smallest difference this
    // run can tell apart, so a delta *of* that size is exactly unresolvable.
    EXPECT_EQ(classifyVerdict(kGoodSamples, kGoodRecovery, 18, 18), Verdict::BelowNoise);
    EXPECT_EQ(classifyVerdict(kGoodSamples, kGoodRecovery, 19, 18), Verdict::Measured);
}

TEST(SpawnCostVerdict, TooFewSamplesOutranksAnOtherwiseCleanMeasurement) {
    EXPECT_EQ(classifyVerdict(kMinSamplesForVerdict - 1, kGoodRecovery, 71, 18),
              Verdict::TooFewSamples);
}

TEST(SpawnCostVerdict, AnUnrecoveredControlOutranksAnOtherwiseCleanMeasurement) {
    // The control is the whole licence to quote a delta nobody knows the size
    // of, so losing it disqualifies the run even when the delta looks fine.
    EXPECT_EQ(classifyVerdict(kGoodSamples, 0.9, 71, 18), Verdict::InstrumentUnreliable);
}

}  // namespace
