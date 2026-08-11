#include "core/git/AskpassHelper.h"

#include "core/base/FsUtil.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <thread>

namespace gbm::askpass {

void wire(GitCommand& command, const std::filesystem::path& dir) {
    if (dir.empty()) {
        return;
    }
    auto exe = fsutil::currentExecutablePath();
    if (!exe) {
        return;
    }
    const std::string exePath = exe->string();
    command.envOverrides.emplace_back("GIT_ASKPASS", exePath);
    command.envOverrides.emplace_back("SSH_ASKPASS", exePath);
    // OpenSSH only calls SSH_ASKPASS when it believes no terminal is usable.
    // SSH_ASKPASS_REQUIRE=force (OpenSSH 8.4+) says so unconditionally; DISPLAY
    // being set covers older clients that still gate on it rather than on the
    // absence of a controlling tty. Both are scoped to this one invocation via
    // envOverrides, never to the process as a whole.
    command.envOverrides.emplace_back("SSH_ASKPASS_REQUIRE", "force");
    command.envOverrides.emplace_back("DISPLAY", ":0");
    command.envOverrides.emplace_back("GBM_ASKPASS_MODE", "1");
    command.envOverrides.emplace_back("GBM_ASKPASS_DIR", dir.string());
}

std::filesystem::path makeRequestDir() {
    std::error_code ec;
    const auto base = std::filesystem::temp_directory_path(ec);
    if (ec) {
        return {};
    }
    static std::atomic<std::uint64_t> counter{0};
    const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto dir =
        base / ("gbm-askpass-" + std::to_string(now) + "-" + std::to_string(counter.fetch_add(1)));
    std::filesystem::create_directories(dir, ec);
    if (ec) {
        return {};
    }
    return dir;
}

int runClientForDir(const std::filesystem::path& dir, const std::string& prompt) {
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    // Written to a temp file and renamed into place rather than written
    // directly to kRequestFile: the app-side watcher (AskpassWatcher /
    // capi::AskpassPoller) polls for kRequestFile's mere existence, so a
    // direct write would let it observe the file after creation but before
    // `prompt` is fully flushed, reading a truncated or empty prompt. A
    // same-directory rename is atomic on every platform this app targets,
    // so the watcher only ever sees kRequestFile fully written or not at
    // all.
    const std::filesystem::path requestPath = dir / std::string(kRequestFile);
    const std::filesystem::path tmpPath = dir / (std::string(kRequestFile) + ".tmp");
    {
        std::ofstream request(tmpPath, std::ios::binary | std::ios::trunc);
        if (!request) {
            return 1;
        }
        request << prompt;
    }
    std::filesystem::rename(tmpPath, requestPath, ec);
    if (ec) {
        return 1;
    }

    const auto responsePath = dir / std::string(kResponseFile);
    const auto cancelPath = dir / std::string(kCancelFile);
    const auto deadline = std::chrono::steady_clock::now() + kResponseTimeout;

    while (std::chrono::steady_clock::now() < deadline) {
        if (std::filesystem::exists(cancelPath, ec)) {
            return 1;
        }
        if (std::filesystem::exists(responsePath, ec)) {
            auto content = fsutil::readSmallFile(responsePath);
            std::filesystem::remove(responsePath, ec);
            std::filesystem::remove(dir / std::string(kRequestFile), ec);
            if (!content) {
                return 1;
            }
            std::fwrite(content->data(), 1, content->size(), stdout);
            std::fputc('\n', stdout);
            std::fflush(stdout);
            return 0;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(150));
    }
    return 1;
}

int runClient(int argc, char** argv) {
    const char* dirEnv = std::getenv("GBM_ASKPASS_DIR");
    if (dirEnv == nullptr || *dirEnv == '\0') {
        return 1;
    }
    const std::string prompt = argc > 1 ? argv[1] : "";
    return runClientForDir(std::filesystem::path(dirEnv), prompt);
}

}  // namespace gbm::askpass
