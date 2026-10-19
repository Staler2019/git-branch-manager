#include "core/git/AskpassHelper.h"

#include "core/base/FsUtil.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <thread>

#ifndef _WIN32
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>
#endif

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
    command.envOverrides.emplace_back("GBM_ASKPASS_DIR", fsutil::utf8FromPath(dir));
}

std::filesystem::path makeRequestDir() {
    std::error_code ec;
    const auto base = std::filesystem::temp_directory_path(ec);
    if (ec) {
        return {};
    }
#ifndef _WIN32
    // mkdtemp: an unpredictable name, created 0700, and failing rather than
    // reusing a directory that already exists. On Linux the base is the
    // shared /tmp, and the response file in here is the user's password.
    std::string pattern = fsutil::utf8FromPath(base / "gbm-askpass-XXXXXX");
    if (::mkdtemp(pattern.data()) == nullptr) {
        return {};
    }
    return fsutil::pathFromUtf8(pattern);
#else
    // %TEMP% is already per-user with an owner-only ACL. create_directory()
    // reports an existing directory as `false`, never reused.
    static std::atomic<std::uint64_t> counter{0};
    for (int attempt = 0; attempt < 16; ++attempt) {
        const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
        const auto dir = base / ("gbm-askpass-" + std::to_string(now) + "-" +
                                 std::to_string(counter.fetch_add(1)));
        if (std::filesystem::create_directory(dir, ec)) {
            return dir;
        }
        if (ec) {
            return {};
        }
    }
    return {};
#endif
}

bool writeHandshakeFile(const std::filesystem::path& dir,
                        std::string_view fileName,
                        std::string_view content) {
    // Written to a temp file and renamed into place: the other side polls for
    // the file's mere existence, so a direct write would let it read a
    // truncated or empty prompt or secret. A same-directory rename is atomic
    // on every platform this app targets.
    const std::filesystem::path target = dir / std::string(fileName);
    const std::filesystem::path tmp = dir / (std::string(fileName) + ".tmp");
#ifndef _WIN32
    // 0600 from the moment it exists; O_NOFOLLOW so a planted link is never
    // written through.
    const int fd = ::open(fsutil::utf8FromPath(tmp).c_str(),
                          O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
                          0600);
    if (fd < 0) {
        return false;
    }
    const char* data = content.data();
    std::size_t left = content.size();
    while (left > 0) {
        const ssize_t written = ::write(fd, data, left);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            ::close(fd);
            return false;
        }
        data += written;
        left -= static_cast<std::size_t>(written);
    }
    if (::close(fd) != 0) {
        return false;
    }
#else
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out) {
            return false;
        }
        out.write(content.data(), static_cast<std::streamsize>(content.size()));
        if (!out) {
            return false;
        }
    }
#endif
    std::error_code ec;
    std::filesystem::rename(tmp, target, ec);
    return !ec;
}

int runClientForDir(const std::filesystem::path& dir, const std::string& prompt) {
    std::error_code ec;
    // Never created here: a directory nobody is watching would leave this
    // process polling for kResponseTimeout with no one to answer it.
    if (!std::filesystem::is_directory(dir, ec)) {
        return 1;
    }
    // The app-side watcher (capi::AskpassPoller) polls for kRequestFile's
    // mere existence; writeHandshakeFile() makes it appear whole or not at
    // all.
    if (!writeHandshakeFile(dir, kRequestFile, prompt)) {
        return 1;
    }

    const auto responsePath = dir / std::string(kResponseFile);
    const auto cancelPath = dir / std::string(kCancelFile);
    const auto deadline = std::chrono::steady_clock::now() + kResponseTimeout;

    while (std::chrono::steady_clock::now() < deadline) {
        // AskpassPoller::stop() removes the directory at the end of every
        // operation, including a cancelled one whose git was killed under
        // this process: gone means nobody will ever answer.
        if (!std::filesystem::exists(dir, ec)) {
            return 1;
        }
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
    // The parent wrote this variable as UTF-8, widened into a wide
    // environment block (ProcessRunner's buildEnvironmentBlock). On Windows the
    // narrow getenv() would hand it back in the active code page, which loses
    // a Chinese temp directory; the wide read returns it exactly.
#if defined(_WIN32)
    const wchar_t* dirEnv = ::_wgetenv(L"GBM_ASKPASS_DIR");
    if (dirEnv == nullptr || *dirEnv == L'\0') {
        return 1;
    }
    const std::filesystem::path dir(dirEnv);
#else
    const char* dirEnv = std::getenv("GBM_ASKPASS_DIR");
    if (dirEnv == nullptr || *dirEnv == '\0') {
        return 1;
    }
    const std::filesystem::path dir = fsutil::pathFromUtf8(dirEnv);
#endif
    const std::string prompt = argc > 1 ? argv[1] : "";
    return runClientForDir(dir, prompt);
}

}  // namespace gbm::askpass
