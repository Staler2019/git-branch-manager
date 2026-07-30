#include "core/discovery/SkipRules.h"

#include "core/base/FsUtil.h"

#include <algorithm>
#include <cctype>

namespace gbm {

SkipRules::SkipRules() {
    builtin_ = {
        // Dependency and build trees: enormous, and never contain a repository
        // the user is looking for.
        "node_modules",
        ".venv",
        "venv",
        "__pycache__",
        ".tox",
        ".mypy_cache",
        ".pytest_cache",
        "build",
        "build-*",
        "cmake-build-*",
        "out",
        "target",
        "dist",
        "bin",
        "obj",
        ".gradle",
        ".cache",
        ".ccache",
        "Pods",
        "vendor",
        ".terraform",
        ".next",
        ".nuxt",
        ".svelte-kit",
        ".parcel-cache",
        ".turbo",
        "bower_components",
        "Carthage",
        // Version-control internals: descending into these would report a
        // repository's own object store as another repository.
        ".git",
        ".svn",
        ".hg",
#if defined(_WIN32)
        "$RECYCLE.BIN",
        "System Volume Information",
        "Temp",
        "AppData",
#elif defined(__APPLE__)
        "Library",
        ".Trash",
        ".Spotlight-V100",
        ".fseventsd",
#else
        ".Trash",
        "proc",
        "sys",
        "dev",
#endif
    };
}

bool SkipRules::matchesPattern(std::string_view name, std::string_view pattern) {
    if (pattern.empty()) {
        return false;
    }
    if (pattern.back() == '*') {
        const std::string_view prefix = pattern.substr(0, pattern.size() - 1);
        if (name.size() < prefix.size()) {
            return false;
        }
        return fsutil::pathsEquivalent(name.substr(0, prefix.size()), prefix);
    }
    return fsutil::pathsEquivalent(name, pattern);
}

bool SkipRules::shouldSkipName(std::string_view name) const {
    const auto matches = [name](const std::string& pattern) {
        return matchesPattern(name, pattern);
    };
    return std::any_of(builtin_.begin(), builtin_.end(), matches) ||
           std::any_of(user_.begin(), user_.end(), matches);
}

bool SkipRules::shouldSkip(const std::filesystem::path& directory) const {
    return shouldSkipName(directory.filename().string());
}

void SkipRules::addPattern(std::string pattern) {
    if (!pattern.empty()) {
        user_.push_back(std::move(pattern));
    }
}

void SkipRules::clearUserPatterns() {
    user_.clear();
}

}  // namespace gbm
