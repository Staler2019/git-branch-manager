#include "core/base/FsUtil.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <system_error>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#if defined(__linux__)
#include <sys/vfs.h>
#elif defined(__APPLE__)
#include <sys/mount.h>
#include <sys/param.h>
#endif
#endif

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

namespace gbm::fsutil {

namespace {

// [[maybe_unused]]: only reachable from the `if constexpr
// (caseInsensitiveFilesystem())` branches below, which the compiler
// discards entirely on Linux (see FsUtil.h) -- but `if constexpr` still
// requires the name to be declared even in the discarded branch of a
// non-template function, so this cannot be conditionally compiled away the
// same way its callers are discarded; the attribute just tells compilers
// that flag "unneeded internal declaration" (Clang) that this is expected.
[[maybe_unused]] std::string foldCase(std::string_view input) {
    std::string out(input);
    std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return out;
}

}  // namespace

std::optional<FileId> fileIdOf(const std::filesystem::path& path) {
#if defined(_WIN32)
    const std::filesystem::path safe = longPathSafe(path);
    HANDLE handle = ::CreateFileW(safe.c_str(),
                                  0,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                  nullptr,
                                  OPEN_EXISTING,
                                  FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
                                  nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        return std::nullopt;
    }
    FILE_ID_INFO info{};
    const BOOL ok = ::GetFileInformationByHandleEx(handle, FileIdInfo, &info, sizeof(info));
    ::CloseHandle(handle);
    if (!ok) {
        return std::nullopt;
    }
    FileId id;
    id.volume = info.VolumeSerialNumber;
    std::memcpy(&id.high, info.FileId.Identifier, sizeof(std::uint64_t));
    std::memcpy(&id.low, info.FileId.Identifier + sizeof(std::uint64_t), sizeof(std::uint64_t));
    return id;
#else
    struct stat st {};

    if (::lstat(path.c_str(), &st) != 0) {
        return std::nullopt;
    }
    FileId id;
    id.volume = static_cast<std::uint64_t>(st.st_dev);
    id.high = 0;
    id.low = static_cast<std::uint64_t>(st.st_ino);
    return id;
#endif
}

std::optional<std::filesystem::path> currentExecutablePath() {
#if defined(_WIN32)
    std::wstring buffer(MAX_PATH, L'\0');
    for (;;) {
        const DWORD written =
            ::GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (written == 0) {
            return std::nullopt;
        }
        if (written < buffer.size()) {
            buffer.resize(written);
            return std::filesystem::path(buffer);
        }
        buffer.resize(buffer.size() * 2);
    }
#elif defined(__APPLE__)
    std::uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::string buffer(size, '\0');
    if (_NSGetExecutablePath(buffer.data(), &size) != 0) {
        return std::nullopt;
    }
    if (!buffer.empty() && buffer.back() == '\0') {
        buffer.pop_back();
    }
    std::error_code ec;
    auto resolved = std::filesystem::canonical(buffer, ec);
    return ec ? std::filesystem::path(buffer) : resolved;
#else
    std::error_code ec;
    auto resolved = std::filesystem::canonical("/proc/self/exe", ec);
    if (ec) {
        return std::nullopt;
    }
    return resolved;
#endif
}

bool pathsEquivalent(std::string_view a, std::string_view b) {
    if constexpr (caseInsensitiveFilesystem()) {
        return foldCase(a) == foldCase(b);
    } else {
        return a == b;
    }
}

std::string canonicalKey(const std::filesystem::path& path) {
    std::string text = path.lexically_normal().generic_string();
    while (text.size() > 1 && text.back() == '/') {
        text.pop_back();
    }
    if constexpr (caseInsensitiveFilesystem()) {
        return foldCase(text);
    } else {
        return text;
    }
}

std::filesystem::path longPathSafe(const std::filesystem::path& path) {
#if defined(_WIN32)
    // Only absolute paths can take the \\?\ prefix, and it must not be applied
    // twice or to a UNC path in the short form.
    std::wstring native = path.native();
    if (native.size() < 4 || native.compare(0, 4, L"\\\\?\\") != 0) {
        std::error_code ec;
        std::filesystem::path absolute = std::filesystem::absolute(path, ec);
        if (!ec) {
            std::wstring text = absolute.make_preferred().native();
            if (text.size() >= 2 && text.compare(0, 2, L"\\\\") == 0) {
                return std::filesystem::path(L"\\\\?\\UNC\\" + text.substr(2));
            }
            return std::filesystem::path(L"\\\\?\\" + text);
        }
    }
    return path;
#else
    return path;
#endif
}

bool isLinkLike(const std::filesystem::directory_entry& entry) {
    std::error_code ec;
    if (entry.is_symlink(ec)) {
        return true;
    }
#if defined(_WIN32)
    // Junctions are not symlinks as far as std::filesystem is concerned, but
    // they can absolutely form a cycle, so treat every reparse point as a link.
    const DWORD attributes = ::GetFileAttributesW(longPathSafe(entry.path()).c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        return true;
    }
#endif
    return false;
}

bool isCloudPlaceholder(const std::filesystem::directory_entry& entry) {
#if defined(_WIN32)
    const DWORD attributes = ::GetFileAttributesW(longPathSafe(entry.path()).c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        return false;
    }
    // Touching these pulls the content down from the cloud provider. A scan over
    // a synced folder would otherwise download gigabytes.
    constexpr DWORD kRecallOnDataAccess = 0x00400000;  // FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
    constexpr DWORD kRecallOnOpen = 0x00040000;        // FILE_ATTRIBUTE_RECALL_ON_OPEN
    constexpr DWORD kOffline = FILE_ATTRIBUTE_OFFLINE;
    return (attributes & (kRecallOnDataAccess | kRecallOnOpen | kOffline)) != 0;
#else
    (void)entry;
    return false;
#endif
}

bool isNetworkPath(const std::filesystem::path& path) {
#if defined(_WIN32)
    std::error_code ec;
    std::filesystem::path absolute = std::filesystem::absolute(path, ec);
    if (ec) {
        return false;
    }
    const std::wstring native = absolute.make_preferred().native();
    if (native.size() >= 2 && native.compare(0, 2, L"\\\\") == 0) {
        return true;  // UNC share
    }
    if (native.size() >= 3 && native[1] == L':') {
        const std::wstring root = native.substr(0, 3);
        return ::GetDriveTypeW(root.c_str()) == DRIVE_REMOTE;
    }
    return false;
#elif defined(__APPLE__)
    struct statfs info {};

    if (::statfs(path.c_str(), &info) != 0) {
        return false;
    }
    const std::string_view name(info.f_fstypename);
    return name == "nfs" || name == "smbfs" || name == "cifs" || name == "afpfs" ||
           name == "webdav";
#elif defined(__linux__)
    struct statfs info {};

    if (::statfs(path.c_str(), &info) != 0) {
        return false;
    }
    constexpr auto kNfsSuper = 0x6969;
    constexpr auto kSmbSuper = 0x517B;
    constexpr auto kCifsMagic = 0xFF534D42;
    const auto type = static_cast<unsigned long>(info.f_type);
    return type == kNfsSuper || type == kSmbSuper || type == kCifsMagic;
#else
    (void)path;
    return false;
#endif
}

std::optional<std::int64_t> modifiedTimeNs(const std::filesystem::path& path) {
#if defined(_WIN32)
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!::GetFileAttributesExW(longPathSafe(path).c_str(), GetFileExInfoStandard, &data)) {
        return std::nullopt;
    }
    ULARGE_INTEGER value;
    value.LowPart = data.ftLastWriteTime.dwLowDateTime;
    value.HighPart = data.ftLastWriteTime.dwHighDateTime;
    // FILETIME is 100ns ticks since 1601; convert to ns since the Unix epoch.
    constexpr std::uint64_t kEpochDelta = 116444736000000000ULL;
    if (value.QuadPart < kEpochDelta) {
        return 0;
    }
    return static_cast<std::int64_t>((value.QuadPart - kEpochDelta) * 100ULL);
#else
    struct stat st {};

    if (::stat(path.c_str(), &st) != 0) {
        return std::nullopt;
    }
#if defined(__APPLE__)
    return static_cast<std::int64_t>(st.st_mtimespec.tv_sec) * 1000000000LL +
           st.st_mtimespec.tv_nsec;
#else
    return static_cast<std::int64_t>(st.st_mtim.tv_sec) * 1000000000LL + st.st_mtim.tv_nsec;
#endif
#endif
}

std::filesystem::path pathFromUtf8(std::string_view utf8) {
    return std::filesystem::path(
        std::u8string(reinterpret_cast<const char8_t*>(utf8.data()), utf8.size()));
}

std::optional<std::string> readSmallFile(const std::filesystem::path& path, std::size_t maxBytes) {
    std::error_code ec;
    const auto size = std::filesystem::file_size(longPathSafe(path), ec);
    if (ec || size > maxBytes) {
        return std::nullopt;
    }

#if defined(_WIN32)
    FILE* file = ::_wfopen(longPathSafe(path).c_str(), L"rb");
#else
    FILE* file = std::fopen(path.c_str(), "rb");
#endif
    if (file == nullptr) {
        return std::nullopt;
    }

    std::string contents;
    contents.resize(static_cast<std::size_t>(size));
    const std::size_t read =
        contents.empty() ? 0 : std::fread(contents.data(), 1, contents.size(), file);
    std::fclose(file);
    if (read != contents.size()) {
        return std::nullopt;
    }
    return contents;
}

}  // namespace gbm::fsutil
