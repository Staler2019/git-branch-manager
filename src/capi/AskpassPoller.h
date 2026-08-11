#pragma once

// A Qt-free equivalent of app/bridge/AskpassWatcher.{h,cpp}: polls a
// per-request directory (see core/git/AskpassHelper.h) for a credential
// prompt a blocked `git` subprocess is waiting on, and writes back whatever
// gbm_provide_credential()/gbm_cancel_credential() decides. Runs its own
// background thread rather than hooking into an event loop -- capi has none
// of its own, unlike the Qt app's QTimer-driven original. See
// Session::beginAskpass()/endAskpass() for how a Session wires this in.

#include <atomic>
#include <filesystem>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

namespace gbm::capi {

class AskpassPoller {
public:
    ~AskpassPoller();

    /// Starts watching `dir` for a request file, invoking `onPrompt` (from
    /// the poller's own background thread) each time a new prompt appears.
    /// A no-op if `dir` is empty -- what a caller gets when
    /// askpass::makeRequestDir() failed, matching AskpassWatcher::start().
    /// Stops any previously-started watch first.
    void start(std::filesystem::path dir, std::function<void(std::string)> onPrompt);

    /// Stops watching and removes the request directory. Safe to call
    /// whether or not a prompt is currently outstanding, and whether or not
    /// start() was ever called -- every Session completion path calls this
    /// unconditionally (see submitWorkingCopyOperation's onAlways hook).
    void stop();

    /// Answers the outstanding prompt, if any. Also re-arms the poller for a
    /// follow-up prompt in the same operation (e.g. a password after a
    /// username), since git can ask more than once per invocation.
    void answer(const std::string& secret);

    /// Dismisses the outstanding prompt, if any; the blocked git subprocess
    /// fails cleanly, exactly as if no credential helper were configured.
    void cancelPrompt();

private:
    void pollLoop();

    std::mutex mutex_;
    std::filesystem::path dir_;
    std::function<void(std::string)> onPrompt_;
    bool requestSeen_ = false;

    std::atomic<bool> running_{false};
    std::thread thread_;
};

}  // namespace gbm::capi
