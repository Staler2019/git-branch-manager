#include "capi/AskpassPoller.h"

#include "core/base/FsUtil.h"
#include "core/git/AskpassHelper.h"

#include <chrono>

namespace gbm::capi {

AskpassPoller::~AskpassPoller() {
    stop();
}

void AskpassPoller::start(std::filesystem::path dir, std::function<void(std::string)> onPrompt) {
    stop();
    if (dir.empty()) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        dir_ = std::move(dir);
        onPrompt_ = std::move(onPrompt);
        requestSeen_ = false;
    }
    running_ = true;
    thread_ = std::thread([this] { pollLoop(); });
}

void AskpassPoller::stop() {
    running_ = false;
    if (thread_.joinable()) {
        thread_.join();
    }

    std::filesystem::path dirToRemove;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        dirToRemove = std::move(dir_);
        dir_.clear();
        onPrompt_ = nullptr;
        requestSeen_ = false;
    }
    if (!dirToRemove.empty()) {
        // Cancel first, so a client still waiting fails on its next poll
        // even if remove_all() below cannot take the whole directory (a
        // Windows file still open); the client also gives up once the
        // directory is gone.
        askpass::writeHandshakeFile(dirToRemove, askpass::kCancelFile, "x");
        std::error_code ec;
        std::filesystem::remove_all(dirToRemove, ec);
    }
}

void AskpassPoller::pollLoop() {
    while (running_.load()) {
        std::filesystem::path requestPath;
        bool seen = false;
        std::function<void(std::string)> onPrompt;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (dir_.empty()) {
                return;
            }
            requestPath = dir_ / std::string(askpass::kRequestFile);
            seen = requestSeen_;
            onPrompt = onPrompt_;
        }

        std::error_code ec;
        if (seen) {
            // The askpass client deletes its own request file once it has
            // read a response; seeing it gone is how a follow-up prompt
            // (e.g. a password after a username) gets noticed.
            if (!std::filesystem::exists(requestPath, ec)) {
                std::lock_guard<std::mutex> lock(mutex_);
                requestSeen_ = false;
            }
        } else if (auto content = fsutil::readSmallFile(requestPath)) {
            {
                std::lock_guard<std::mutex> lock(mutex_);
                requestSeen_ = true;
            }
            if (onPrompt) {
                onPrompt(*content);
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(150));
    }
}

void AskpassPoller::answer(const std::string& secret) {
    std::filesystem::path dir;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        dir = dir_;
    }
    if (dir.empty()) {
        return;
    }
    askpass::writeHandshakeFile(dir, askpass::kResponseFile, secret);
}

void AskpassPoller::cancelPrompt() {
    std::filesystem::path dir;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        dir = dir_;
    }
    if (dir.empty()) {
        return;
    }
    askpass::writeHandshakeFile(dir, askpass::kCancelFile, "x");
}

}  // namespace gbm::capi
