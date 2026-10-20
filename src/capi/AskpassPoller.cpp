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
        answered_ = false;
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
        answered_ = false;
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
        std::filesystem::path responsePath;
        bool seen = false;
        bool answered = false;
        std::function<void(std::string)> onPrompt;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (dir_.empty()) {
                return;
            }
            requestPath = dir_ / std::string(askpass::kRequestFile);
            responsePath = dir_ / std::string(askpass::kResponseFile);
            seen = requestSeen_;
            answered = answered_;
            onPrompt = onPrompt_;
        }

        std::error_code ec;
        if (seen) {
            // A follow-up prompt (a password after a username) is noticed two
            // ways. The answered response being taken is the one that always
            // works: git starts the next client within milliseconds, so its
            // request file usually replaces the old one inside a single poll
            // and is never seen missing. The request file being gone covers a
            // client that exited without an answer.
            const bool responseTaken = answered && !std::filesystem::exists(responsePath, ec);
            if (responseTaken || !std::filesystem::exists(requestPath, ec)) {
                std::lock_guard<std::mutex> lock(mutex_);
                requestSeen_ = false;
                answered_ = false;
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
    // Written under the lock: the client can take the response the moment it
    // exists, and pollLoop() re-arms under this same lock. Setting answered_
    // after letting go would let it land on the *next* prompt and re-raise it.
    std::lock_guard<std::mutex> lock(mutex_);
    if (dir_.empty()) {
        return;
    }
    if (askpass::writeHandshakeFile(dir_, askpass::kResponseFile, secret)) {
        answered_ = true;
    }
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
