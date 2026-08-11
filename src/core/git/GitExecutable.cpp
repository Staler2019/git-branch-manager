#include "core/git/GitExecutable.h"

#include "core/base/Logging.h"
#include "core/git/IProcessRunner.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>

#if defined(_WIN32)
#include <windows.h>
#endif

namespace gbm {

namespace {

bool looksLikeWslShim(const std::filesystem::path& candidate) {
#if defined(_WIN32)
    // The WSL interop shim cannot see Windows repository paths the way a native
    // git can, so accepting it produces confusing "not a git repository" errors.
    const std::string text = candidate.string();
    std::string lowered;
    lowered.reserve(text.size());
    std::transform(text.begin(), text.end(), std::back_inserter(lowered), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return lowered.find("\\windowsapps\\") != std::string::npos ||
           lowered.find("\\lxss\\") != std::string::npos;
#else
    (void)candidate;
    return false;
#endif
}

#if defined(_WIN32)
std::filesystem::path gitFromRegistry() {
    for (HKEY root : {HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER}) {
        HKEY key = nullptr;
        if (::RegOpenKeyExW(root, L"SOFTWARE\\GitForWindows", 0, KEY_READ, &key) != ERROR_SUCCESS) {
            continue;
        }
        wchar_t buffer[MAX_PATH]{};
        DWORD size = sizeof(buffer);
        DWORD type = 0;
        const LSTATUS status = ::RegQueryValueExW(
            key, L"InstallPath", nullptr, &type, reinterpret_cast<LPBYTE>(buffer), &size);
        ::RegCloseKey(key);
        if (status == ERROR_SUCCESS && type == REG_SZ) {
            std::filesystem::path install(buffer);
            std::error_code ec;
            auto candidate = install / "cmd" / "git.exe";
            if (std::filesystem::exists(candidate, ec)) {
                return candidate;
            }
        }
    }
    return {};
}
#endif

std::vector<std::filesystem::path> fromEnvironmentPath() {
    std::vector<std::filesystem::path> found;
    const char* pathVar = std::getenv("PATH");
    if (pathVar == nullptr) {
        return found;
    }
#if defined(_WIN32)
    constexpr char kSeparator = ';';
    const char* kExeName = "git.exe";
#else
    constexpr char kSeparator = ':';
    const char* kExeName = "git";
#endif
    std::string_view remaining(pathVar);
    while (!remaining.empty()) {
        const std::size_t split = remaining.find(kSeparator);
        const std::string_view entry = remaining.substr(0, split);
        if (!entry.empty()) {
            std::error_code ec;
            std::filesystem::path candidate = std::filesystem::path(entry) / kExeName;
            if (std::filesystem::exists(candidate, ec) && !looksLikeWslShim(candidate)) {
                found.push_back(candidate);
            }
        }
        if (split == std::string_view::npos) {
            break;
        }
        remaining.remove_prefix(split + 1);
    }
    return found;
}

}  // namespace

GitVersion GitVersion::parse(std::string_view versionOutput) {
    // Handles "git version 2.43.0" and vendor suffixes such as
    // "git version 2.39.3 (Apple Git-146)" or "2.45.1.windows.1".
    GitVersion version;
    std::size_t index = 0;
    while (index < versionOutput.size() &&
           !(std::isdigit(static_cast<unsigned char>(versionOutput[index])) != 0)) {
        ++index;
    }

    int* fields[3] = {&version.major, &version.minor, &version.patch};
    for (int field = 0; field < 3 && index < versionOutput.size(); ++field) {
        int value = 0;
        bool sawDigit = false;
        while (index < versionOutput.size() &&
               std::isdigit(static_cast<unsigned char>(versionOutput[index])) != 0) {
            value = value * 10 + (versionOutput[index] - '0');
            ++index;
            sawDigit = true;
        }
        if (!sawDigit) {
            break;
        }
        *fields[field] = value;
        if (index < versionOutput.size() && versionOutput[index] == '.') {
            ++index;
        } else {
            break;
        }
    }
    return version;
}

std::vector<std::string> GitInstallation::warnings() const {
    std::vector<std::string> result;
    if (!capabilities.fsMonitor) {
        result.push_back(
            "Git " + version.toString() +
            " has no built-in filesystem monitor (needs 2.37 or newer). Working-copy status will "
            "be slower on large repositories.");
    }
    if (!capabilities.mergeTreeWriteTree) {
        result.push_back("Git " + version.toString() +
                         " cannot preview merge conflicts (needs 2.38 or newer).");
    }
    if (!capabilities.changedPathBloom) {
        result.push_back("Git " + version.toString() +
                         " has no changed-path Bloom filters (needs 2.24 or newer). File history "
                         "will be slower.");
    }
    return result;
}

GitCapabilities GitExecutable::capabilitiesFor(const GitVersion& version) {
    GitCapabilities caps;
    caps.commitGraphSplit = version >= GitVersion{2, 24, 0};
    caps.changedPathBloom = version >= GitVersion{2, 24, 0};
    caps.sparseIndex = version >= GitVersion{2, 32, 0};
    caps.fsMonitor = version >= GitVersion{2, 37, 0};
    caps.mergeTreeWriteTree = version >= GitVersion{2, 38, 0};
    return caps;
}

GitResult<GitInstallation> GitExecutable::probe(const std::filesystem::path& candidate) {
    std::error_code ec;
    if (candidate.empty() || !std::filesystem::exists(candidate, ec)) {
        return fail(GitError::Code::NotFound, "No git executable at " + candidate.string());
    }

    // A candidate found by name (PATH lookup, a hardcoded fallback) can still be
    // unusable: present but missing the executable bit for this user, or
    // blocked from running by an OS-level policy (e.g. macOS sandboxing denies
    // process-exec on an otherwise perfectly normal binary). Catching that here
    // means the resulting error names the file instead of surfacing a generic
    // spawn failure with no path attached.
    const auto permissions = std::filesystem::status(candidate, ec).permissions();
    if (ec) {
        return fail(GitError::Code::Io, "Could not read permissions for " + candidate.string());
    }
    constexpr std::filesystem::perms kAnyExecute = std::filesystem::perms::owner_exec |
                                                    std::filesystem::perms::group_exec |
                                                    std::filesystem::perms::others_exec;
    if ((permissions & kAnyExecute) == std::filesystem::perms::none) {
        return fail(GitError::Code::Io, candidate.string() + " is not executable");
    }

    auto runner = makeProcessRunner(candidate);
    GitCommand command;
    command.args = {"--version"};
    command.timeout = std::chrono::seconds(10);

    auto result = runner->run(command, CancellationToken{});
    if (!result) {
        return fail(std::move(result).error());
    }

    GitInstallation installation;
    installation.executable = candidate;
    installation.version = GitVersion::parse(result->out);
    installation.capabilities = capabilitiesFor(installation.version);

    if (installation.version.major == 0) {
        return fail(GitError::Code::ParseError,
                    "Could not read the version reported by " + candidate.string(),
                    result->out);
    }
    return installation;
}

std::vector<std::filesystem::path> GitExecutable::searchPath() {
    std::vector<std::filesystem::path> candidates;

#if defined(_WIN32)
    if (auto registryPath = gitFromRegistry(); !registryPath.empty()) {
        candidates.push_back(registryPath);
    }
#endif

    for (auto& fromPath : fromEnvironmentPath()) {
        candidates.push_back(std::move(fromPath));
    }

#if defined(_WIN32)
    candidates.emplace_back("C:/Program Files/Git/cmd/git.exe");
    candidates.emplace_back("C:/Program Files (x86)/Git/cmd/git.exe");
#elif defined(__APPLE__)
    candidates.emplace_back("/opt/homebrew/bin/git");
    candidates.emplace_back("/usr/local/bin/git");
    candidates.emplace_back("/usr/bin/git");
#else
    candidates.emplace_back("/usr/bin/git");
    candidates.emplace_back("/usr/local/bin/git");
#endif

    // De-duplicate while preserving priority order.
    std::vector<std::filesystem::path> unique;
    for (const auto& candidate : candidates) {
        const bool seen = std::any_of(
            unique.begin(), unique.end(), [&candidate](const std::filesystem::path& existing) {
                return existing == candidate;
            });
        if (!seen) {
            unique.push_back(candidate);
        }
    }
    return unique;
}

GitResult<GitInstallation> GitExecutable::detect(const std::filesystem::path& preferred) {
    // An explicit setting always wins, and its failure is reported rather than
    // silently falling back: if the user pinned a git, a silent substitution
    // would be worse than an error.
    if (!preferred.empty()) {
        auto probed = probe(preferred);
        if (!probed) {
            return probed;
        }
        if (!probed->isUsable()) {
            return fail(GitError::Code::Unsupported,
                        "Git " + probed->version.toString() + " at " + preferred.string() +
                            " is too old; " + GitInstallation::minimumSupported().toString() +
                            " or newer is required");
        }
        return probed;
    }

    const std::vector<std::filesystem::path> candidates = searchPath();
    // Every candidate's failure reason is kept, not just the last one tried:
    // with last-write-wins, the final hardcoded fallback's plain "not found"
    // silently overwrote the real reason an earlier, more likely candidate
    // (found via PATH) had failed for — e.g. present but blocked from running
    // by the OS. The aggregated message tells the user which of the several
    // gits it actually looked at, and why each was rejected.
    std::vector<std::string> attempts;
    attempts.reserve(candidates.size());
    for (const auto& candidate : candidates) {
        auto probed = probe(candidate);
        if (!probed) {
            attempts.push_back(candidate.string() + " (" + probed.error().message + ")");
            continue;
        }
        if (!probed->isUsable()) {
            attempts.push_back(candidate.string() + " (Git " + probed->version.toString() +
                               " is too old; " + GitInstallation::minimumSupported().toString() +
                               " or newer is required)");
            continue;
        }
        logMessage(LogLevel::Info,
                   "Using git " + probed->version.toString() + " at " + candidate.string());
        return probed;
    }

    if (attempts.empty()) {
        return fail(GitError::Code::NotFound,
                    "No usable git executable was found and no candidate locations exist for "
                    "this platform");
    }
    std::string message = "No usable git executable was found. Tried: ";
    for (std::size_t i = 0; i < attempts.size(); ++i) {
        if (i > 0) {
            message += "; ";
        }
        message += attempts[i];
    }
    return fail(GitError::Code::NotFound, message);
}

}  // namespace gbm
