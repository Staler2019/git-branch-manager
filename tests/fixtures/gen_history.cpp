// Generates a `git fast-import` stream describing a synthetic repository with a
// controlled branch and merge topology.
//
// This exists because the performance and correctness targets are about *large*
// histories, and creating 200k commits with `git commit` would take hours and
// need a working tree. fast-import ingests 10k-50k commits per second with no
// checkout at all, so a 200k-commit fixture is ~15 seconds and fully
// reproducible from a seed.
//
//   gen_history --commits 200000 --branches 40 --merge-rate 0.08 --seed 42
//       | git -C /tmp/fixture fast-import
//
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

/// A fixed 64-bit PRNG rather than std::mt19937: the generated stream must be
/// byte-identical across platforms and standard library versions, otherwise the
/// golden graph tests would differ between Linux, macOS and Windows.
class SplitMix64 {
public:
    explicit SplitMix64(std::uint64_t seed) : state_(seed) {}

    std::uint64_t next() {
        std::uint64_t z = (state_ += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }

    std::uint32_t below(std::uint32_t bound) {
        return bound == 0 ? 0 : static_cast<std::uint32_t>(next() % bound);
    }

    double unit() { return static_cast<double>(next() >> 11) / 9007199254740992.0; }

private:
    std::uint64_t state_;
};

struct Options {
    int commits = 1000;
    int branches = 8;
    double mergeRate = 0.08;
    int octopusParents = 0;  ///< 0 disables octopus merges.
    double octopusRate = 0.002;
    int tags = 0;
    std::uint64_t seed = 42;
    int filesPerCommit = 1;
};

void printUsage() {
    std::fputs(
        "Usage: gen_history [options] | git -C <repo> fast-import\n"
        "  --commits N          number of commits (default 1000)\n"
        "  --branches N         concurrent side branches (default 8)\n"
        "  --merge-rate F       probability a commit is a merge (default 0.08)\n"
        "  --octopus N          max extra parents for octopus merges (default 0)\n"
        "  --octopus-rate F     probability of an octopus merge (default 0.002)\n"
        "  --tags N             number of tags to create (default 0)\n"
        "  --files N            files touched per commit (default 1)\n"
        "  --seed N             PRNG seed (default 42)\n",
        stderr);
}

bool parseOptions(int argc, char** argv, Options* options) {
    for (int i = 1; i < argc; ++i) {
        const char* arg = argv[i];
        auto needValue = [&i, argc, argv]() -> const char* {
            return i + 1 < argc ? argv[++i] : nullptr;
        };
        if (std::strcmp(arg, "--commits") == 0) {
            const char* value = needValue();
            if (value == nullptr) return false;
            options->commits = std::atoi(value);
        } else if (std::strcmp(arg, "--branches") == 0) {
            const char* value = needValue();
            if (value == nullptr) return false;
            options->branches = std::atoi(value);
        } else if (std::strcmp(arg, "--merge-rate") == 0) {
            const char* value = needValue();
            if (value == nullptr) return false;
            options->mergeRate = std::atof(value);
        } else if (std::strcmp(arg, "--octopus") == 0) {
            const char* value = needValue();
            if (value == nullptr) return false;
            options->octopusParents = std::atoi(value);
        } else if (std::strcmp(arg, "--octopus-rate") == 0) {
            const char* value = needValue();
            if (value == nullptr) return false;
            options->octopusRate = std::atof(value);
        } else if (std::strcmp(arg, "--tags") == 0) {
            const char* value = needValue();
            if (value == nullptr) return false;
            options->tags = std::atoi(value);
        } else if (std::strcmp(arg, "--files") == 0) {
            const char* value = needValue();
            if (value == nullptr) return false;
            options->filesPerCommit = std::atoi(value);
        } else if (std::strcmp(arg, "--seed") == 0) {
            const char* value = needValue();
            if (value == nullptr) return false;
            options->seed = std::strtoull(value, nullptr, 10);
        } else if (std::strcmp(arg, "--help") == 0 || std::strcmp(arg, "-h") == 0) {
            printUsage();
            std::exit(0);
        } else {
            std::fprintf(stderr, "Unknown option: %s\n", arg);
            return false;
        }
    }
    return options->commits > 0 && options->branches > 0;
}

}  // namespace

int main(int argc, char** argv) {
    Options options;
    if (!parseOptions(argc, argv, &options)) {
        printUsage();
        return 2;
    }

    SplitMix64 rng(options.seed);

    // Branch 0 is the trunk. Each entry holds the mark of that branch's tip, or 0
    // for a branch not yet started.
    std::vector<int> branchTip(static_cast<std::size_t>(options.branches), 0);
    int mark = 0;

    // Commit timestamps advance monotonically so `--topo-order` has a sensible
    // date tie-break, matching how real history looks.
    std::int64_t when = 1'000'000'000;

    std::string buffer;
    buffer.reserve(1 << 20);

    auto flush = [&buffer] {
        if (!buffer.empty()) {
            std::fwrite(buffer.data(), 1, buffer.size(), stdout);
            buffer.clear();
        }
    };

    for (int commitIndex = 0; commitIndex < options.commits; ++commitIndex) {
        // Trunk gets the majority of commits; the rest spread over side branches.
        const bool onTrunk = options.branches == 1 || rng.unit() < 0.55;
        const std::size_t branch =
            onTrunk ? 0 : 1 + rng.below(static_cast<std::uint32_t>(options.branches - 1));

        const int firstParent = branchTip[branch];
        std::vector<int> extraParents;

        // A merge takes a second parent from another branch that has commits.
        if (firstParent != 0 && rng.unit() < options.mergeRate) {
            for (std::size_t attempt = 0; attempt < 4; ++attempt) {
                const std::size_t other = rng.below(static_cast<std::uint32_t>(options.branches));
                if (other != branch && branchTip[other] != 0) {
                    extraParents.push_back(branchTip[other]);
                    break;
                }
            }
            // Occasionally make it an octopus, which exercises the lane
            // allocator's right-side fan-out.
            if (!extraParents.empty() && options.octopusParents > 0 &&
                rng.unit() < options.octopusRate) {
                const int extra =
                    1 +
                    static_cast<int>(rng.below(static_cast<std::uint32_t>(options.octopusParents)));
                for (int e = 0; e < extra; ++e) {
                    const std::size_t other =
                        rng.below(static_cast<std::uint32_t>(options.branches));
                    if (other == branch || branchTip[other] == 0) {
                        continue;
                    }
                    const int candidate = branchTip[other];
                    bool duplicate = candidate == firstParent;
                    for (int existing : extraParents) {
                        duplicate = duplicate || existing == candidate;
                    }
                    if (!duplicate) {
                        extraParents.push_back(candidate);
                    }
                }
            }
        }

        ++mark;
        when += 60 + rng.below(600);

        const std::string branchRef =
            branch == 0 ? "refs/heads/main" : "refs/heads/feature/" + std::to_string(branch);

        // Blob first, then the commit referencing it. Inline data keeps the
        // stream self-contained.
        std::string message = "Commit " + std::to_string(commitIndex) + " on " + branchRef;

        buffer += "commit " + branchRef + "\n";
        buffer += "mark :" + std::to_string(mark) + "\n";
        buffer +=
            "author Fixture Author <fixture@example.invalid> " + std::to_string(when) + " +0000\n";
        buffer += "committer Fixture Author <fixture@example.invalid> " + std::to_string(when) +
                  " +0000\n";
        buffer += "data " + std::to_string(message.size()) + "\n";
        buffer += message + "\n";

        if (firstParent != 0) {
            buffer += "from :" + std::to_string(firstParent) + "\n";
        } else if (branch != 0 && branchTip[0] != 0) {
            // A new side branch starts from the current trunk tip, which is what
            // produces a realistic branch-and-rejoin shape.
            buffer += "from :" + std::to_string(branchTip[0]) + "\n";
        }
        for (int parent : extraParents) {
            buffer += "merge :" + std::to_string(parent) + "\n";
        }

        for (int f = 0; f < options.filesPerCommit; ++f) {
            const std::string path =
                "src/file_" + std::to_string(rng.below(500)) + "_" + std::to_string(f) + ".txt";
            const std::string content =
                "line " + std::to_string(commitIndex) + " " + std::to_string(f) + "\n";
            buffer += "M 100644 inline " + path + "\n";
            buffer += "data " + std::to_string(content.size()) + "\n";
            buffer += content;
        }
        buffer += "\n";

        branchTip[branch] = mark;

        if (buffer.size() > (1 << 20)) {
            flush();
        }
    }

    // Tags spread across trunk history, so the ref-count guard and tag decoration
    // paths have something to work with.
    for (int t = 0; t < options.tags; ++t) {
        const int target = 1 + static_cast<int>(rng.below(static_cast<std::uint32_t>(mark)));
        buffer += "reset refs/tags/v0." + std::to_string(t) + "\n";
        buffer += "from :" + std::to_string(target) + "\n\n";
    }

    buffer += "done\n";
    flush();
    std::fflush(stdout);

    std::fprintf(stderr,
                 "gen_history: %d commits, %d branches, seed %llu\n",
                 options.commits,
                 options.branches,
                 static_cast<unsigned long long>(options.seed));
    return 0;
}
