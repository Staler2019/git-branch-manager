#pragma once

#ifdef _WIN32

#include <cstddef>
#include <memory>
#include <optional>
#include <vector>
#include <windows.h>

namespace gbm::win {

/// A `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` that limits what one `CreateProcessW`
/// hands the child to exactly the handles named here.
///
/// **Why.** `bInheritHandles = TRUE` alone passes *every* inheritable handle
/// in the process. Each spawn marks its own pipe write end inheritable, so a
/// spawn on another thread that lands between that `CreatePipe` and its
/// `CloseHandle` takes the write end too; a long-lived child such as
/// `cat-file --batch` then keeps that pipe open, and the reader of the first
/// spawn never sees EOF -- the Windows form of the leak `PosixPipe.h`
/// describes.
///
/// Every handle must be valid and inheritable; duplicates are dropped (a
/// merged stderr names stdout's handle twice). Pass [attributeList] as
/// `STARTUPINFOEXW::lpAttributeList` together with
/// `EXTENDED_STARTUPINFO_PRESENT`. Move-only: the list points into buffers
/// this object owns.
class InheritList {
public:
    static std::optional<InheritList> create(std::vector<HANDLE> handles);

    InheritList(InheritList&& other) noexcept;
    InheritList& operator=(InheritList&&) = delete;
    InheritList(const InheritList&) = delete;
    InheritList& operator=(const InheritList&) = delete;
    ~InheritList();

    LPPROC_THREAD_ATTRIBUTE_LIST attributeList() const noexcept;

private:
    InheritList() = default;

    std::vector<HANDLE> handles_;
    std::unique_ptr<std::byte[]> buffer_;
    bool initialized_ = false;
};

/// An inheritable read handle on `NUL`, for a child with no stdin pipe -- the
/// counterpart of POSIX's `/dev/null`. `GetStdHandle(STD_INPUT_HANDLE)` cannot
/// stand in: a GUI process may have none, and [InheritList] refuses a null or
/// non-inheritable handle. The caller closes it after `CreateProcessW`.
HANDLE openInheritableNul();

}  // namespace gbm::win

#endif
