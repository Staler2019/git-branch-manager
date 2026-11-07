#pragma once

#include <cstdint>

namespace gbm {

/// Whether a crash gets a message box: only while no window of the process is visible
/// (once one is, the next launch tells the user), never in the askpass process (git waits on
/// it and it has no window), never for a stack overflow (the filter runs on that stack), and
/// never when GBM_CRASH_NO_DIALOG is set (tests). Pure, so every OS tests it.
bool shouldShowCrashDialog(std::uint32_t code,
                           bool askpass,
                           bool noDialog,
                           bool anyVisibleWindow) noexcept;

/// Windows: an unhandled SEH exception (access violation and the like) on any thread
/// appends one line to nativeErrorLogPath() -- code, faulting module's file name and
/// offset, thread id, nothing from memory -- then may show a box (shouldShowCrashDialog),
/// then hands on to the filter that was there before, so Windows Error Reporting still
/// runs. Crash time allocates nothing. Called while the library loads, under the loader
/// lock, so it only fills buffers, starts the box's thread and installs the filter.
/// Elsewhere it does nothing.
void installCrashFilter() noexcept;

}  // namespace gbm
