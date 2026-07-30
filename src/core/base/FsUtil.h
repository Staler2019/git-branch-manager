#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace gbm::fsutil {

/// Identity of a directory on disk, used to break symlink/junction cycles during
/// discovery scans. On POSIX this is (device, inode); on Windows it is the volume
/// serial plus FILE_ID_128, since junctions make path comparison unreliable.
struct FileId {
    std::uint64_t volume = 0;
    std::uint64_t high = 0;
    std::uint64_t low = 0;

    friend bool operator==(const FileId& a, const FileId& b) noexcept {
        return a.volume == b.volume && a.high == b.high && a.low == b.low;
    }
};

struct FileIdHash {
    std::size_t operator()(const FileId& id) const noexcept {
        std::uint64_t h = id.volume * 0x9e3779b97f4a7c15ULL;
        h ^= id.high + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
        h ^= id.low + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
        return static_cast<std::size_t>(h);
    }
};

std::optional<FileId> fileIdOf(const std::filesystem::path& path);

/// True when the platform's filesystem comparison is case-insensitive. Windows
/// and macOS are, Linux is not. Callers must use this rather than assuming, or
/// path de-duplication silently misbehaves on one of the three targets.
constexpr bool caseInsensitiveFilesystem() {
#if defined(_WIN32) || defined(__APPLE__)
    return true;
#else
    return false;
#endif
}

/// Path equality under the platform's own rules.
bool pathsEquivalent(std::string_view a, std::string_view b);

/// Canonical key for the discovery cache: lexically normalised, trailing
/// separator stripped, and case-folded where the platform demands it.
std::string canonicalKey(const std::filesystem::path& path);

/// Wraps a path so Win32 accepts it beyond MAX_PATH (260). Returns the input
/// unchanged on POSIX. Every Windows filesystem call in the scanner goes through
/// this, otherwise deep trees throw partway through a scan.
std::filesystem::path longPathSafe(const std::filesystem::path& path);

/// True for symlinks and, on Windows, for any reparse point — junctions report
/// themselves as plain directories through std::filesystem, so relying on
/// is_symlink() alone lets a scan loop forever.
bool isLinkLike(const std::filesystem::directory_entry& entry);

/// True when the path lives on a placeholder/cloud-backed file (OneDrive, and
/// similar). Reading these triggers a download, so scans must skip them.
bool isCloudPlaceholder(const std::filesystem::directory_entry& entry);

/// True when the path lives on a network filesystem. Parallel readdir hurts
/// rather than helps there, so the scanner drops to a single worker.
bool isNetworkPath(const std::filesystem::path& path);

/// Modification time in nanoseconds since the epoch, or nullopt if unavailable.
/// The discovery cache uses this as its validity witness.
std::optional<std::int64_t> modifiedTimeNs(const std::filesystem::path& path);

/// Reads a small file (refs, HEAD, .git pointer files) fully into a string.
/// Refuses anything over `maxBytes` so a hostile or corrupt repo cannot make us
/// allocate unboundedly.
std::optional<std::string> readSmallFile(const std::filesystem::path& path,
                                         std::size_t maxBytes = 64 * 1024);

}  // namespace gbm::fsutil
