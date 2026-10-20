#include "support/DirLink.h"

#ifdef _WIN32
#include <cstring>
#include <string>
#include <vector>
#include <windows.h>
#include <winioctl.h>
#endif

namespace gbm::testing {

#ifdef _WIN32
namespace {

void put16(std::vector<unsigned char>& buffer, std::size_t at, std::size_t value) {
    const auto word = static_cast<WORD>(value);
    std::memcpy(buffer.data() + at, &word, sizeof word);
}

}  // namespace

// REPARSE_DATA_BUFFER's mount-point form lives in the DDK's ntifs.h, not in
// the SDK, so its layout is written out here byte by byte:
//   DWORD tag | WORD dataLength | WORD reserved          (8-byte header)
//   WORD substituteOffset | WORD substituteLength
//   WORD printOffset      | WORD printLength             (8 bytes)
//   WCHAR paths[]: substitute L'\0' print L'\0'
bool makeDirectoryLink(const std::filesystem::path& target,
                       const std::filesystem::path& link,
                       std::error_code& ec) {
    const std::filesystem::path absolute = std::filesystem::absolute(target, ec);
    if (ec) return false;
    if (!std::filesystem::create_directory(link, ec)) {
        if (!ec) ec = std::make_error_code(std::errc::file_exists);
        return false;
    }
    const std::wstring print = absolute.wstring();
    const std::wstring substitute = L"\\??\\" + print;
    const std::size_t pathBytes = (substitute.size() + 1 + print.size() + 1) * sizeof(wchar_t);
    const std::size_t dataLength = 8 + pathBytes;
    std::vector<unsigned char> buffer(8 + dataLength, 0);
    const DWORD tag = IO_REPARSE_TAG_MOUNT_POINT;
    std::memcpy(buffer.data(), &tag, sizeof tag);
    put16(buffer, 4, dataLength);
    put16(buffer, 8, 0);
    put16(buffer, 10, substitute.size() * sizeof(wchar_t));
    put16(buffer, 12, (substitute.size() + 1) * sizeof(wchar_t));
    put16(buffer, 14, print.size() * sizeof(wchar_t));
    std::memcpy(buffer.data() + 16, substitute.c_str(), (substitute.size() + 1) * sizeof(wchar_t));
    std::memcpy(buffer.data() + 16 + (substitute.size() + 1) * sizeof(wchar_t),
                print.c_str(),
                (print.size() + 1) * sizeof(wchar_t));

    const HANDLE handle = ::CreateFileW(link.wstring().c_str(),
                                        GENERIC_WRITE,
                                        0,
                                        nullptr,
                                        OPEN_EXISTING,
                                        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
                                        nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        ec = std::error_code(static_cast<int>(::GetLastError()), std::system_category());
        std::filesystem::remove(link);
        return false;
    }
    DWORD returned = 0;
    const BOOL ok = ::DeviceIoControl(handle,
                                      FSCTL_SET_REPARSE_POINT,
                                      buffer.data(),
                                      static_cast<DWORD>(buffer.size()),
                                      nullptr,
                                      0,
                                      &returned,
                                      nullptr);
    const DWORD error = ::GetLastError();
    ::CloseHandle(handle);
    if (!ok) {
        ec = std::error_code(static_cast<int>(error), std::system_category());
        std::filesystem::remove(link);
        return false;
    }
    ec.clear();
    return true;
}
#else
bool makeDirectoryLink(const std::filesystem::path& target,
                       const std::filesystem::path& link,
                       std::error_code& ec) {
    std::filesystem::create_directory_symlink(target, link, ec);
    return !ec;
}
#endif

}  // namespace gbm::testing
