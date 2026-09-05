// What does the job object added to WindowsChild::spawn() actually cost per
// spawn?
//
// This tool exists because the previous round answered that question wrong and
// said so out loud. Three Windows CI runs of the same 151 git-spawning tests
// read 133.71s / 177.67s / 136.38s, and "job object costs 33%" was reported
// off the middle one. The control group used to justify it was 175 tests that
// spawn nothing, averaging 34ms each -- almost entirely fixed cost, and
// therefore barely sensitive to how fast the machine was that hour. It swung
// 1.58x on its own. Calibrating a second-scale effect against a ruler with no
// markings is what produced the wrong number, and
// docs/reports/windows-process-cost.md had already recorded that CI wall-clock
// on this project is not trustworthy at that resolution.
//
// So this measures the thing directly, and the design is mostly controls:
//
//   * **A/A null arm.** Two identical no-job arms, interleaved with everything
//     else. Their difference is what this machine, this run, can resolve --
//     measured, never assumed. A job-object delta smaller than that is
//     reported as an upper bound and never as a point estimate. That single
//     rule is the direct fix for "33%".
//   * **An injected known delay.** A third arm is the no-job arm plus a
//     deliberate ~kInjectedDelayUs busy-wait. If the instrument cannot recover
//     a delay it was told about, to within 50%, it prints
//     `verdict=instrument-unreliable` and its A/B number must not be quoted.
//     A control that cannot disagree with the hypothesis is not a control
//     ([TEST-fixture-cannot-disagree] applied to a measurement) -- and *that*
//     is precisely what the 175-test control group was.
//   * **Interleaving, not blocks.** Every arm runs once per iteration, so
//     whatever is making the machine slow this second is making all arms slow.
//     Block order reverses on odd iterations so a systematic
//     first-in-the-pair advantage cannot accumulate.
//   * **Per-spawn assertions.** Exit code 0 and the exact stdout bytes, every
//     time; plus `IsProcessInJob` on every job arm sample. A failed spawn is
//     fast, and an assign that silently did not happen makes the two arms
//     identical -- both would read as "the job object is free".
//   * **A real denominator.** `git --version` is timed in the same interleave,
//     so the overhead can be expressed as a fraction of a real git spawn
//     rather than of a trivial one. windows-process-cost.md diagnosed its own
//     earlier mistake as assuming cost(cmd.exe) ~ cost(git.exe); this does not
//     repeat it.
//
// The timing idioms (odd sample counts, discarded warm-up, median rather than
// mean or best-of-N, one machine-readable summary line) are lifted from
// tools/graph_check.cpp deliberately, rather than a second harness being
// invented next to the first.
//
// Production is not modified to measure it. The job arm re-implements
// WindowsChild::spawn()'s sequence, and any way in which this clone differs
// from production is present in *both* arms and cancels in the difference --
// which is why the difference, and not either arm's absolute number, is the
// output. The `prod_*` arms then go through the real ProcessRunner, so the
// watchdog thread's cost is separated from the job object's; the ledger's
// three-run table carried both at once and never separated them.

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#ifdef _WIN32

#include "core/git/GitCommand.h"
#include "core/git/GitExecutable.h"
#include "core/git/IProcessRunner.h"

#include <windows.h>

namespace {

constexpr int kDefaultIterations = 51;  // Odd: the median is a real sample.
constexpr int kWarmupIterations = 5;    // Discarded; pays for page faults and JIT-free warm caches.
constexpr long long kInjectedDelayUs = 300;
constexpr double kInjectedRecoveryTolerance = 0.5;
constexpr long long kMinSamplesForVerdict = 11;

int gFailures = 0;

void check(bool condition, const std::string& message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message.c_str());
        ++gFailures;
    }
}

long long qpcFrequency() {
    LARGE_INTEGER frequency{};
    ::QueryPerformanceFrequency(&frequency);
    return frequency.QuadPart;
}

long long qpcNow() {
    LARGE_INTEGER counter{};
    ::QueryPerformanceCounter(&counter);
    return counter.QuadPart;
}

long long ticksToMicros(long long ticks, long long frequency) {
    return frequency == 0 ? 0 : (ticks * 1000000) / frequency;
}

/// Spins for roughly `micros`. A sleep would hand the scheduler an excuse to
/// park this thread for a whole quantum, which is a different and much larger
/// delay than the one being injected.
void busyWaitMicros(long long micros, long long frequency) {
    const long long deadline = qpcNow() + (micros * frequency) / 1000000;
    while (qpcNow() < deadline) {
    }
}

long long medianOf(std::vector<long long> values) {
    // Median, not mean and not best-of-N -- graph_check.cpp's reasoning applies
    // unchanged: a mean is dragged by the one sample that got descheduled, and
    // best-of-N systematically flatters whichever arm caught the quietest
    // moment.
    std::sort(values.begin(), values.end());
    return values.empty() ? 0 : values[values.size() / 2];
}

std::wstring widen(const std::string& text) {
    if (text.empty()) {
        return std::wstring();
    }
    const int size =
        ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring wide(static_cast<std::size_t>(size), L'\0');
    ::MultiByteToWideChar(
        CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), wide.data(), size);
    return wide;
}

/// One spawn of `commandLine`, mirroring WindowsChild::spawn()'s sequence:
/// inheritable pipes, CREATE_SUSPENDED, (optionally) job object, ResumeThread,
/// drain stdout, wait, read exit code.
///
/// Returns elapsed ticks, or -1 if anything about the spawn was not exactly as
/// expected -- the caller turns that into a failure rather than a sample.
long long timeOneSpawn(const std::wstring& commandLine, bool useJob, std::string* stdoutText) {
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE outRead = nullptr;
    HANDLE outWrite = nullptr;
    if (::CreatePipe(&outRead, &outWrite, &sa, 0) == 0) {
        return -1;
    }
    ::SetHandleInformation(outRead, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = outWrite;
    si.hStdError = outWrite;
    si.hStdInput = ::GetStdHandle(STD_INPUT_HANDLE);

    std::wstring mutableCommandLine = commandLine;
    PROCESS_INFORMATION pi{};

    const long long start = qpcNow();
    const BOOL ok =
        ::CreateProcessW(nullptr,
                         mutableCommandLine.data(),
                         nullptr,
                         nullptr,
                         TRUE,
                         CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED | CREATE_NO_WINDOW,
                         nullptr,
                         nullptr,
                         &si,
                         &pi);
    ::CloseHandle(outWrite);
    if (ok == 0) {
        ::CloseHandle(outRead);
        return -1;
    }

    HANDLE job = nullptr;
    if (useJob) {
        job = ::CreateJobObjectW(nullptr, nullptr);
        if (job != nullptr && ::AssignProcessToJobObject(job, pi.hProcess) == 0) {
            ::CloseHandle(job);
            job = nullptr;
        }
        // Without this the two arms are the same code path with different
        // wall-clock luck, and the tool would confidently report the job
        // object as free. Checked on every sample, not once.
        BOOL inJob = FALSE;
        if (job == nullptr || ::IsProcessInJob(pi.hProcess, job, &inJob) == 0 || inJob == FALSE) {
            ::ResumeThread(pi.hThread);
            ::CloseHandle(pi.hThread);
            ::WaitForSingleObject(pi.hProcess, INFINITE);
            ::CloseHandle(pi.hProcess);
            if (job != nullptr) {
                ::CloseHandle(job);
            }
            ::CloseHandle(outRead);
            return -1;
        }
    }

    ::ResumeThread(pi.hThread);
    ::CloseHandle(pi.hThread);

    stdoutText->clear();
    char buffer[512];
    for (;;) {
        DWORD read = 0;
        if (::ReadFile(outRead, buffer, sizeof(buffer), &read, nullptr) == 0 || read == 0) {
            break;
        }
        stdoutText->append(buffer, read);
    }
    ::CloseHandle(outRead);

    ::WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD exitCode = 1;
    ::GetExitCodeProcess(pi.hProcess, &exitCode);
    ::CloseHandle(pi.hProcess);
    // Closed on the success path too, exactly as production does -- which is
    // why production deliberately omits JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE.
    if (job != nullptr) {
        ::CloseHandle(job);
    }
    const long long elapsed = qpcNow() - start;

    return exitCode == 0 ? elapsed : -1;
}

struct Arm {
    const char* name;
    std::vector<long long> samples;
};

}  // namespace

int main(int argc, char** argv) {
    int iterations = kDefaultIterations;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--iterations") == 0 && i + 1 < argc) {
            iterations = std::atoi(argv[i + 1]);
        }
    }
    if (iterations % 2 == 0) {
        ++iterations;  // Odd, so the median is an observation rather than an average.
    }

    const char* childPath = std::getenv("GBM_EXIT_NOW_EXE");
    check(childPath != nullptr && *childPath != '\0',
          "GBM_EXIT_NOW_EXE is not set; nothing to spawn");
    if (gFailures != 0) {
        return 1;
    }

    const long long frequency = qpcFrequency();
    check(frequency > 0, "QueryPerformanceFrequency returned 0");
    if (gFailures != 0) {
        return 1;
    }

    const std::wstring childCommand = L"\"" + widen(childPath) + L"\"";

    // CI runners commonly run the whole job inside a job object already, and a
    // nested assign is a different kernel path from a top-level one. Printed
    // rather than corrected for: it is a property of where the number was
    // taken, and a reader comparing two runs needs to know it matched.
    BOOL parentInJob = FALSE;
    ::IsProcessInJob(::GetCurrentProcess(), nullptr, &parentInJob);

    Arm rawNoJob{"raw_nojob", {}};
    Arm rawJob{"raw_job", {}};
    Arm nullArm{"raw_nojob_aa", {}};
    Arm injected{"raw_nojob_plus_delay", {}};

    const int total = iterations + kWarmupIterations;
    for (int i = 0; i < total; ++i) {
        const bool record = i >= kWarmupIterations;
        // Reversing on odd iterations keeps a systematic
        // whoever-goes-first advantage from accumulating into the difference.
        const bool jobFirst = (i % 2) == 1;
        std::string out;

        long long a = -1;
        long long b = -1;
        if (jobFirst) {
            b = timeOneSpawn(childCommand, /*useJob=*/true, &out);
            check(out == "ok\n", "job arm child produced unexpected stdout");
            a = timeOneSpawn(childCommand, /*useJob=*/false, &out);
            check(out == "ok\n", "no-job arm child produced unexpected stdout");
        } else {
            a = timeOneSpawn(childCommand, /*useJob=*/false, &out);
            check(out == "ok\n", "no-job arm child produced unexpected stdout");
            b = timeOneSpawn(childCommand, /*useJob=*/true, &out);
            check(out == "ok\n", "job arm child produced unexpected stdout");
        }

        const long long aa = timeOneSpawn(childCommand, /*useJob=*/false, &out);
        check(out == "ok\n", "A/A arm child produced unexpected stdout");

        const long long injectedStart = qpcNow();
        const long long inj = timeOneSpawn(childCommand, /*useJob=*/false, &out);
        check(out == "ok\n", "injected-delay arm child produced unexpected stdout");
        busyWaitMicros(kInjectedDelayUs, frequency);
        const long long injElapsed = inj < 0 ? -1 : (qpcNow() - injectedStart);

        check(a >= 0 && b >= 0 && aa >= 0 && injElapsed >= 0, "a spawn failed mid-loop");
        if (gFailures != 0) {
            return 1;
        }
        if (record) {
            rawNoJob.samples.push_back(a);
            rawJob.samples.push_back(b);
            nullArm.samples.push_back(aa);
            injected.samples.push_back(injElapsed);
        }
    }

    const long long noJobUs = ticksToMicros(medianOf(rawNoJob.samples), frequency);
    const long long jobUs = ticksToMicros(medianOf(rawJob.samples), frequency);
    const long long nullUs = ticksToMicros(medianOf(nullArm.samples), frequency);
    const long long injectedUs = ticksToMicros(medianOf(injected.samples), frequency);

    // The instrument's own resolution for this run: two arms that differ by
    // nothing at all. Anything under it is noise, and is reported as such.
    const long long resolutionUs = std::max<long long>(std::llabs(noJobUs - nullUs), 1);
    const long long jobDeltaUs = jobUs - noJobUs;
    const long long recoveredUs = injectedUs - noJobUs;
    const double recoveryError =
        static_cast<double>(std::llabs(recoveredUs - kInjectedDelayUs)) / kInjectedDelayUs;

    // A real git spawn through the real ProcessRunner, so the overhead above
    // can be stated as a fraction of something a user actually waits for --
    // and, in the same loop, the *second* A/B this tool owes.
    //
    // The two `prod_*` arms differ in one field: `prod_timeout` sets a
    // deadline, so `WindowsChild::pump()` starts a watchdog thread and
    // duplicates a thread handle for it; `prod_notimeout` leaves both
    // deadlines at 0, which is the branch that starts no thread at all
    // ([CPP-windows-terminate-hangs-join]). Their difference is therefore the
    // watchdog's per-spawn cost with the job object held constant -- both arms
    // create one, because production always does.
    //
    // This separation is the whole point: the ledger's third Windows run
    // carried the job object *and* the watchdog at once and reported 1.02x for
    // the pair, so neither was ever attributed. Two arms differing in one
    // field is what makes an attribution possible.
    long long gitUs = 0;
    long long gitTimeoutUs = 0;
    {
        auto installation = gbm::GitExecutable::detect();
        if (installation && !installation->executable.empty()) {
            auto runner = gbm::makeProcessRunner(installation->executable);

            const auto timeOneGit = [&](bool withDeadline) -> long long {
                gbm::GitCommand command;
                command.args = {"--version"};
                // 30s vs 0: the only difference between the two arms.
                command.timeout = withDeadline ? std::chrono::milliseconds(30000)
                                               : std::chrono::milliseconds(0);
                command.idleTimeout = std::chrono::milliseconds(0);
                const long long start = qpcNow();
                const auto result = runner->run(command);
                const long long elapsed = qpcNow() - start;
                check(static_cast<bool>(result),
                      "`git --version` failed while measuring the denominator");
                return elapsed;
            };

            std::vector<long long> noTimeoutSamples;
            std::vector<long long> timeoutSamples;
            for (int i = 0; i < kWarmupIterations + iterations; ++i) {
                // Same alternation as the raw arms, for the same reason.
                const bool deadlineFirst = (i % 2) == 1;
                const long long first = timeOneGit(deadlineFirst);
                const long long second = timeOneGit(!deadlineFirst);
                if (gFailures != 0) {
                    return 1;
                }
                if (i >= kWarmupIterations) {
                    timeoutSamples.push_back(deadlineFirst ? first : second);
                    noTimeoutSamples.push_back(deadlineFirst ? second : first);
                }
            }
            gitUs = ticksToMicros(medianOf(noTimeoutSamples), frequency);
            gitTimeoutUs = ticksToMicros(medianOf(timeoutSamples), frequency);
        }
    }

    // Reported against the same resolution the job-object delta is judged by:
    // this arm pair is measured with the same instrument, on the same run.
    const long long watchdogDeltaUs = gitTimeoutUs - gitUs;
    const bool watchdogResolved = gitUs > 0 && std::llabs(watchdogDeltaUs) > resolutionUs;

    const char* verdict = "measured";
    if (static_cast<long long>(rawJob.samples.size()) < kMinSamplesForVerdict) {
        verdict = "too-few-samples";
    } else if (recoveryError > kInjectedRecoveryTolerance) {
        // The instrument could not find a delay it was told the size of, so
        // nothing it says about a delay nobody told it about is usable.
        verdict = "instrument-unreliable";
    } else if (std::llabs(jobDeltaUs) <= resolutionUs) {
        verdict = "below-noise";
    }

    std::fprintf(stderr,
                 "job-object spawn cost (%d iterations, %d discarded warm-up):\n"
                 "  raw_nojob median   = %lldus\n"
                 "  raw_job   median   = %lldus\n"
                 "  A/A null  median   = %lldus  -> resolution %lldus\n"
                 "  injected %lldus     -> recovered %lldus (error %.0f%%)\n"
                 "  prod_notimeout     = %lldus  (git --version, no watchdog)\n"
                 "  prod_timeout       = %lldus  (git --version, watchdog armed)\n"
                 "  watchdog delta     = %lldus  (%s)\n"
                 "  parent already in a job: %s\n",
                 iterations,
                 kWarmupIterations,
                 noJobUs,
                 jobUs,
                 nullUs,
                 resolutionUs,
                 kInjectedDelayUs,
                 recoveredUs,
                 recoveryError * 100.0,
                 gitUs,
                 gitTimeoutUs,
                 watchdogDeltaUs,
                 watchdogResolved ? "resolved" : "below this run's resolution",
                 parentInJob ? "yes" : "no");

    // The watchdog arm gets the same treatment as the job-object arm rather
    // than a looser one: a point estimate only when the run could resolve it,
    // an upper bound otherwise. Two arms measured by one instrument must not
    // be held to two standards.
    char watchdogField[128];
    std::snprintf(watchdogField,
                  sizeof(watchdogField),
                  watchdogResolved ? "watchdog_delta_us=%lld"
                                   : "watchdog_delta_upper_bound_us=%lld",
                  watchdogResolved ? watchdogDeltaUs
                                   : std::max<long long>(std::llabs(watchdogDeltaUs), resolutionUs));

    // One machine-readable line for the nightly Step Summary. Below the
    // instrument's resolution it carries an upper bound and **no point
    // estimate** -- printing one is exactly how "33%" happened.
    if (std::strcmp(verdict, "measured") == 0) {
        const double fraction =
            gitUs > 0 ? static_cast<double>(jobDeltaUs) / static_cast<double>(gitUs) : 0.0;
        std::fprintf(stderr,
                     "job-object-ab: verdict=measured job_overhead_us=%lld resolution_us=%lld "
                     "git_spawn_us=%lld overhead_fraction_of_git=%.4f %s parent_in_job=%d "
                     "iterations=%d\n",
                     jobDeltaUs,
                     resolutionUs,
                     gitUs,
                     fraction,
                     watchdogField,
                     parentInJob ? 1 : 0,
                     iterations);

        const char* gateText = std::getenv("GBM_MAX_JOB_OVERHEAD_FRACTION");
        const double gate = gateText != nullptr ? std::atof(gateText) : 0.0;
        if (gate > 0.0) {
            check(fraction <= gate,
                  "job-object overhead is " + std::to_string(fraction) +
                      " of a git spawn, over the " + std::to_string(gate) + " gate");
        }
    } else {
        std::fprintf(stderr,
                     "job-object-ab: verdict=%s job_overhead_upper_bound_us=%lld "
                     "resolution_us=%lld git_spawn_us=%lld %s parent_in_job=%d iterations=%d\n",
                     verdict,
                     std::max<long long>(std::llabs(jobDeltaUs), resolutionUs),
                     resolutionUs,
                     gitUs,
                     watchdogField,
                     parentInJob ? 1 : 0,
                     iterations);
        // Deliberately not a failure. "This machine cannot resolve it" is a
        // real and useful answer, and the honest one on a noisy CI runner;
        // turning it into a red build would only invite someone to widen the
        // instrument until it always says something.
    }

    return gFailures == 0 ? 0 : 1;
}

#else  // _WIN32

// Compiled on every platform on purpose. The job object it measures exists
// only on Windows, but a tool that only compiles in one CI job is a tool that
// rots in the other five -- and this one is already the debt from a round that
// got its measurement wrong once.
int main() {
    std::fprintf(stderr, "job-object-ab: verdict=not-applicable (Windows only)\n");
    return 0;
}

#endif  // _WIN32
