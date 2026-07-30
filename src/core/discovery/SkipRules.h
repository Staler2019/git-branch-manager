#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace gbm {

/// Directory names a discovery scan should not descend into.
///
/// This list is doing real work, not tidying up. A scan of a developer's home
/// directory that walks into `node_modules` trees can multiply the directory
/// count by an order of magnitude, and the platform entries prevent worse: on
/// Windows, touching a OneDrive placeholder triggers a download, so scanning a
/// synced folder without these rules can pull gigabytes over the network.
class SkipRules {
public:
    SkipRules();

    /// True when this directory must not be entered.
    bool shouldSkip(const std::filesystem::path& directory) const;

    bool shouldSkipName(std::string_view name) const;

    void addPattern(std::string pattern);

    void clearUserPatterns();

    const std::vector<std::string>& builtinPatterns() const { return builtin_; }

    const std::vector<std::string>& userPatterns() const { return user_; }

    /// Supports a single trailing '*' wildcard, which covers the cases that
    /// matter (`build-*`, `cmake-build-*`) without pulling in a regex engine.
    static bool matchesPattern(std::string_view name, std::string_view pattern);

private:
    std::vector<std::string> builtin_;
    std::vector<std::string> user_;
};

}  // namespace gbm
