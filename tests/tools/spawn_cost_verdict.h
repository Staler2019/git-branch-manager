// The A/B run's verdict, split out of `spawn_cost_win.cpp` so that something
// other than a Windows nightly can disagree with it.
//
// The tool's whole body is one `#ifdef _WIN32` and it runs on exactly one
// scheduled job, so the branch that refuses to publish an impossible number is
// reached only on a noisy Windows runner -- which is to say, in practice,
// never. That is [TEST-fixture-cannot-disagree] applied to the instrument
// itself: a correctness rule with no tier able to contradict it. Everything
// here is arithmetic over four scalars, so `SpawnCostVerdictTest.cpp` covers it
// on every platform while the tool stays Windows-only.
#pragma once

namespace gbm::spawncost {

/// Below this many kept samples the medians are not worth a verdict at all.
inline constexpr long long kMinSamplesForVerdict = 11;

/// The injected-delay control must come back within this fraction of the delay
/// it was told to inject. Miss it and nothing the run says about a delay
/// *nobody* told it about is usable either.
inline constexpr double kInjectedRecoveryTolerance = 0.5;

enum class Verdict {
    Measured,
    TooFewSamples,
    InstrumentUnreliable,
    BelowNoise,
};

/// Classify one A/B run. `jobDeltaUs` is signed, and stays signed.
///
/// Creating and assigning a job object cannot make a spawn *faster*, so a
/// delta at or below this run's own resolution -- negative ones very much
/// included -- is noise rather than a cost. Comparing `llabs(jobDeltaUs)`
/// instead lets a noisy night publish
///
///     verdict=measured job_overhead_us=-50 overhead_fraction_of_git=-0.002
///
/// which is an impossible claim, is promoted unattended into the job's step
/// summary, and passes a `fraction <= gate` check trivially because a negative
/// number is below any threshold. A significantly negative reading is evidence
/// that the resolution is *understated*, never evidence of a negative cost.
inline Verdict classifyVerdict(long long keptSamples,
                               double recoveryError,
                               long long jobDeltaUs,
                               long long resolutionUs) {
    if (keptSamples < kMinSamplesForVerdict) {
        return Verdict::TooFewSamples;
    }
    if (recoveryError > kInjectedRecoveryTolerance) {
        return Verdict::InstrumentUnreliable;
    }
    if (jobDeltaUs <= resolutionUs) {
        return Verdict::BelowNoise;
    }
    return Verdict::Measured;
}

/// The wire spelling. `spawn_cost_win.cpp` prints these into the
/// `job-object-ab:` line that `perf-nightly.yml` greps for, so they are a
/// contract with that workflow and not just a debug label.
inline const char* verdictName(Verdict verdict) {
    switch (verdict) {
        case Verdict::Measured:
            return "measured";
        case Verdict::TooFewSamples:
            return "too-few-samples";
        case Verdict::InstrumentUnreliable:
            return "instrument-unreliable";
        case Verdict::BelowNoise:
            return "below-noise";
    }
    return "unknown";
}

}  // namespace gbm::spawncost
