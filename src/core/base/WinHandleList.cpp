#include "core/base/WinHandleList.h"

#ifdef _WIN32

#include <algorithm>

namespace gbm::win {

std::optional<InheritList> InheritList::create(std::vector<HANDLE> handles) {
    std::sort(handles.begin(), handles.end());
    handles.erase(std::unique(handles.begin(), handles.end()), handles.end());

    InheritList list;
    list.handles_ = std::move(handles);

    SIZE_T size = 0;
    ::InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
    list.buffer_ = std::make_unique<std::byte[]>(size);
    if (!::InitializeProcThreadAttributeList(list.attributeList(), 1, 0, &size)) {
        return std::nullopt;
    }
    list.initialized_ = true;
    if (!::UpdateProcThreadAttribute(list.attributeList(),
                                     0,
                                     PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                     list.handles_.data(),
                                     list.handles_.size() * sizeof(HANDLE),
                                     nullptr,
                                     nullptr)) {
        return std::nullopt;
    }
    return list;
}

InheritList::InheritList(InheritList&& other) noexcept
    : handles_(std::move(other.handles_)),
      buffer_(std::move(other.buffer_)),
      initialized_(other.initialized_) {
    other.initialized_ = false;
}

InheritList::~InheritList() {
    if (initialized_) {
        ::DeleteProcThreadAttributeList(attributeList());
    }
}

LPPROC_THREAD_ATTRIBUTE_LIST InheritList::attributeList() const noexcept {
    return reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(buffer_.get());
}

HANDLE openInheritableNul() {
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;
    const HANDLE nul = ::CreateFileW(L"NUL",
                                     GENERIC_READ,
                                     FILE_SHARE_READ | FILE_SHARE_WRITE,
                                     &sa,
                                     OPEN_EXISTING,
                                     FILE_ATTRIBUTE_NORMAL,
                                     nullptr);
    return nul == INVALID_HANDLE_VALUE ? nullptr : nul;
}

}  // namespace gbm::win

#endif
