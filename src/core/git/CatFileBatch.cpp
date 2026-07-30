#include "core/git/CatFileBatch.h"

#include "core/base/Logging.h"
#include "core/base/ThreadCheck.h"
#include "core/git/GitCommand.h"

#include <algorithm>
#include <cstring>
#include <utility>

#if defined(_WIN32)
#include <windows.h>
#else
#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char** environ;
#endif

namespace gbm {

namespace {

/// Reads exactly `count` bytes, looping over short reads. The batch protocol is
/// length-prefixed, so a short read is normal and must not be mistaken for EOF.
template <class ReadFn>
bool readExact(ReadFn&& readSome, char* out, std::size_t count) {
    std::size_t done = 0;
    while (done < count) {
        const std::ptrdiff_t n = readSome(out + done, count - done);
        if (n <= 0) {
            return false;
        }
        done += static_cast<std::size_t>(n);
    }
    return true;
}

}  // namespace

/// Owns the child process and its two pipes. Kept in the .cpp so no platform
/// header leaks into the rest of the codebase.
class CatFileBatch::Impl {
public:
    ~Impl() { close(); }

    GitResult<void> spawn(const std::filesystem::path& git, const RepoPaths& paths) {
        std::vector<std::string> argv;
        argv.push_back(git.string());
        for (auto& flag : GitCommand::globalFlags()) {
            argv.push_back(std::move(flag));
        }
        argv.emplace_back("-C");
        argv.push_back(paths.commandDir().string());
        argv.emplace_back("cat-file");
        argv.emplace_back("--batch");

#if defined(_WIN32)
        return spawnWindows(argv);
#else
        return spawnPosix(argv);
#endif
    }

    bool write(std::string_view data) {
#if defined(_WIN32)
        std::size_t offset = 0;
        while (offset < data.size()) {
            DWORD written = 0;
            if (!::WriteFile(stdinHandle_,
                             data.data() + offset,
                             static_cast<DWORD>(data.size() - offset),
                             &written,
                             nullptr) ||
                written == 0) {
                return false;
            }
            offset += written;
        }
        return true;
#else
        std::size_t offset = 0;
        while (offset < data.size()) {
            const ssize_t n = ::write(stdinFd_, data.data() + offset, data.size() - offset);
            if (n <= 0) {
                if (n < 0 && errno == EINTR) {
                    continue;
                }
                return false;
            }
            offset += static_cast<std::size_t>(n);
        }
        return true;
#endif
    }

    std::ptrdiff_t readSome(char* out, std::size_t count) {
#if defined(_WIN32)
        DWORD read = 0;
        if (!::ReadFile(stdoutHandle_, out, static_cast<DWORD>(count), &read, nullptr)) {
            return -1;
        }
        return static_cast<std::ptrdiff_t>(read);
#else
        for (;;) {
            const ssize_t n = ::read(stdoutFd_, out, count);
            if (n < 0 && errno == EINTR) {
                continue;
            }
            return n;
        }
#endif
    }

    /// Reads up to and including the next LF. Used for the header line only,
    /// which is short, so byte-at-a-time reads cost nothing measurable.
    bool readLine(std::string& out) {
        out.clear();
        char c = 0;
        for (;;) {
            const std::ptrdiff_t n = readSome(&c, 1);
            if (n <= 0) {
                return false;
            }
            if (c == '\n') {
                return true;
            }
            out.push_back(c);
            if (out.size() > 64 * 1024) {
                return false;  // Not a header line; the protocol has desynchronised.
            }
        }
    }

    bool isRunning() const {
#if defined(_WIN32)
        return process_ != nullptr;
#else
        return pid_ > 0;
#endif
    }

    void close() {
#if defined(_WIN32)
        if (stdinHandle_ != nullptr) {
            ::CloseHandle(stdinHandle_);
            stdinHandle_ = nullptr;
        }
        if (stdoutHandle_ != nullptr) {
            ::CloseHandle(stdoutHandle_);
            stdoutHandle_ = nullptr;
        }
        if (process_ != nullptr) {
            ::WaitForSingleObject(process_, 2000);
            ::TerminateProcess(process_, 0);
            ::CloseHandle(process_);
            process_ = nullptr;
        }
#else
        if (stdinFd_ >= 0) {
            ::close(stdinFd_);
            stdinFd_ = -1;
        }
        if (stdoutFd_ >= 0) {
            ::close(stdoutFd_);
            stdoutFd_ = -1;
        }
        if (pid_ > 0) {
            // Closing stdin makes cat-file exit on its own; reap it so we do not
            // leak a zombie per repository open.
            int status = 0;
            for (int i = 0; i < 20; ++i) {
                const pid_t result = ::waitpid(pid_, &status, WNOHANG);
                if (result == pid_ || (result < 0 && errno == ECHILD)) {
                    pid_ = -1;
                    return;
                }

                struct timespec ts {
                    0, 10 * 1000 * 1000
                };

                ::nanosleep(&ts, nullptr);
            }
            ::kill(pid_, SIGKILL);
            ::waitpid(pid_, &status, 0);
            pid_ = -1;
        }
#endif
    }

private:
#if defined(_WIN32)
    GitResult<void> spawnWindows(const std::vector<std::string>& argv) {
        SECURITY_ATTRIBUTES sa{};
        sa.nLength = sizeof(sa);
        sa.bInheritHandle = TRUE;

        HANDLE outRead = nullptr, outWrite = nullptr, inRead = nullptr, inWrite = nullptr;
        if (!::CreatePipe(&outRead, &outWrite, &sa, 0) ||
            !::CreatePipe(&inRead, &inWrite, &sa, 0)) {
            return fail(GitError::Code::SpawnFailed, "Could not create a pipe for git cat-file");
        }
        ::SetHandleInformation(outRead, HANDLE_FLAG_INHERIT, 0);
        ::SetHandleInformation(inWrite, HANDLE_FLAG_INHERIT, 0);

        std::wstring commandLine;
        for (std::size_t i = 0; i < argv.size(); ++i) {
            if (i != 0) {
                commandLine.push_back(L' ');
            }
            const int needed = ::MultiByteToWideChar(
                CP_UTF8, 0, argv[i].data(), static_cast<int>(argv[i].size()), nullptr, 0);
            std::wstring wide(static_cast<std::size_t>(needed), L'\0');
            ::MultiByteToWideChar(
                CP_UTF8, 0, argv[i].data(), static_cast<int>(argv[i].size()), wide.data(), needed);
            const bool needsQuotes = wide.find_first_of(L" \t\"") != std::wstring::npos;
            if (needsQuotes) {
                commandLine.push_back(L'"');
                commandLine += wide;
                commandLine.push_back(L'"');
            } else {
                commandLine += wide;
            }
        }

        STARTUPINFOW si{};
        si.cb = sizeof(si);
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdOutput = outWrite;
        si.hStdError = outWrite;
        si.hStdInput = inRead;

        PROCESS_INFORMATION pi{};
        std::vector<wchar_t> mutableCommandLine(commandLine.begin(), commandLine.end());
        mutableCommandLine.push_back(L'\0');
        const BOOL ok = ::CreateProcessW(nullptr,
                                         mutableCommandLine.data(),
                                         nullptr,
                                         nullptr,
                                         TRUE,
                                         CREATE_NO_WINDOW,
                                         nullptr,
                                         nullptr,
                                         &si,
                                         &pi);
        ::CloseHandle(outWrite);
        ::CloseHandle(inRead);
        if (!ok) {
            ::CloseHandle(outRead);
            ::CloseHandle(inWrite);
            return fail(GitError::Code::SpawnFailed, "Could not start git cat-file --batch");
        }
        ::CloseHandle(pi.hThread);
        process_ = pi.hProcess;
        stdoutHandle_ = outRead;
        stdinHandle_ = inWrite;
        return {};
    }

    HANDLE process_ = nullptr;
    HANDLE stdoutHandle_ = nullptr;
    HANDLE stdinHandle_ = nullptr;
#else
    GitResult<void> spawnPosix(const std::vector<std::string>& argv) {
        int outPipe[2] = {-1, -1};
        int inPipe[2] = {-1, -1};
        if (::pipe(outPipe) != 0) {
            return fail(GitError::Code::SpawnFailed,
                        "Could not create a pipe for git cat-file",
                        std::strerror(errno));
        }
        if (::pipe(inPipe) != 0) {
            ::close(outPipe[0]);
            ::close(outPipe[1]);
            return fail(GitError::Code::SpawnFailed,
                        "Could not create a pipe for git cat-file",
                        std::strerror(errno));
        }

        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions, inPipe[0], STDIN_FILENO);
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
        posix_spawn_file_actions_addclose(&actions, inPipe[1]);
        posix_spawn_file_actions_addclose(&actions, outPipe[0]);

        std::vector<char*> rawArgv;
        rawArgv.reserve(argv.size() + 1);
        for (const auto& arg : argv) {
            rawArgv.push_back(const_cast<char*>(arg.c_str()));
        }
        rawArgv.push_back(nullptr);

        pid_t pid = -1;
        const int rc = ::posix_spawnp(&pid, rawArgv[0], &actions, nullptr, rawArgv.data(), environ);
        posix_spawn_file_actions_destroy(&actions);
        ::close(inPipe[0]);
        ::close(outPipe[1]);

        if (rc != 0) {
            ::close(inPipe[1]);
            ::close(outPipe[0]);
            return fail(GitError::Code::SpawnFailed,
                        "Could not start git cat-file --batch",
                        std::strerror(rc));
        }
        pid_ = pid;
        stdinFd_ = inPipe[1];
        stdoutFd_ = outPipe[0];
        return {};
    }

    pid_t pid_ = -1;
    int stdoutFd_ = -1;
    int stdinFd_ = -1;
#endif
};

CatFileBatch::CatFileBatch(std::filesystem::path gitExecutable, RepoPaths paths)
    : git_(std::move(gitExecutable)), paths_(std::move(paths)) {}

CatFileBatch::~CatFileBatch() = default;

GitResult<void> CatFileBatch::start() {
    GBM_ASSERT_NOT_UI_THREAD();
    std::lock_guard<std::mutex> lock(mutex_);
    if (impl_ && impl_->isRunning() && !poisoned_) {
        return {};
    }
    impl_ = std::make_unique<Impl>();
    poisoned_ = false;
    auto spawned = impl_->spawn(git_, paths_);
    if (!spawned) {
        impl_.reset();
        return spawned;
    }
    return {};
}

void CatFileBatch::stop() {
    std::lock_guard<std::mutex> lock(mutex_);
    impl_.reset();
}

bool CatFileBatch::isRunning() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return impl_ && impl_->isRunning() && !poisoned_;
}

GitResult<CatFileBatch::Object> CatFileBatch::read(std::string_view revision) {
    GBM_ASSERT_NOT_UI_THREAD();

    // A revision containing a newline would inject a second request into the
    // protocol stream. Reject rather than sanitise: no legitimate caller does it.
    if (revision.empty() || revision.find('\n') != std::string_view::npos) {
        return fail(GitError::Code::InvalidArgument, "Invalid object revision");
    }

    std::lock_guard<std::mutex> lock(mutex_);
    if (!impl_ || !impl_->isRunning() || poisoned_) {
        impl_ = std::make_unique<Impl>();
        poisoned_ = false;
        if (auto spawned = impl_->spawn(git_, paths_); !spawned) {
            impl_.reset();
            return fail(std::move(spawned).error());
        }
    }

    std::string request(revision);
    request.push_back('\n');
    if (!impl_->write(request)) {
        poisoned_ = true;
        return fail(GitError::Code::Io, "The git cat-file process stopped responding");
    }

    std::string header;
    if (!impl_->readLine(header)) {
        poisoned_ = true;
        return fail(GitError::Code::Io, "The git cat-file process stopped responding");
    }

    // "<oid> missing" / "<oid> ambiguous" leave the stream in a good state, so
    // these are ordinary errors rather than a reason to restart the child.
    if (header.size() > 8 && header.compare(header.size() - 8, 8, " missing") == 0) {
        return fail(GitError::Code::NotFound, "No such object: " + std::string(revision));
    }
    if (header.find(" ambiguous") != std::string::npos) {
        return fail(GitError::Code::InvalidArgument,
                    "Ambiguous object name: " + std::string(revision));
    }

    const std::size_t firstSpace = header.find(' ');
    const std::size_t secondSpace =
        firstSpace == std::string::npos ? std::string::npos : header.find(' ', firstSpace + 1);
    if (firstSpace == std::string::npos || secondSpace == std::string::npos) {
        poisoned_ = true;
        return fail(GitError::Code::ParseError, "Unexpected cat-file response", header);
    }

    Object object;
    object.oid = ObjectId::fromHex(std::string_view(header).substr(0, firstSpace));
    object.type = header.substr(firstSpace + 1, secondSpace - firstSpace - 1);

    std::size_t size = 0;
    for (std::size_t i = secondSpace + 1; i < header.size(); ++i) {
        const char c = header[i];
        if (c < '0' || c > '9') {
            poisoned_ = true;
            return fail(GitError::Code::ParseError, "Unexpected cat-file size", header);
        }
        size = size * 10 + static_cast<std::size_t>(c - '0');
    }

    // Guard against a pathological blob: a 2 GB file must not be pulled into
    // memory just because it happened to be clicked on.
    constexpr std::size_t kMaxObjectBytes = 128u * 1024u * 1024u;
    if (size > kMaxObjectBytes) {
        // The payload still has to be drained, or every later response is
        // misaligned. Discard it in chunks instead of allocating it.
        std::vector<char> scratch(64 * 1024);
        std::size_t remaining = size + 1;  // +1 for the trailing LF
        while (remaining > 0) {
            const std::size_t want = std::min(remaining, scratch.size());
            const std::ptrdiff_t n = impl_->readSome(scratch.data(), want);
            if (n <= 0) {
                poisoned_ = true;
                break;
            }
            remaining -= static_cast<std::size_t>(n);
        }
        return fail(
            GitError::Code::TooLarge,
            "Object is too large to display (" + std::to_string(size / (1024 * 1024)) + " MB)");
    }

    object.content.resize(size);
    auto readSome = [this](char* out, std::size_t count) { return impl_->readSome(out, count); };
    if (size > 0 && !readExact(readSome, object.content.data(), size)) {
        poisoned_ = true;
        return fail(GitError::Code::Io, "The git cat-file process stopped mid-object");
    }

    char trailing = 0;
    if (!readExact(readSome, &trailing, 1) || trailing != '\n') {
        poisoned_ = true;
        return fail(GitError::Code::ParseError, "Malformed cat-file record terminator");
    }
    return object;
}

GitResult<CommitMeta> CatFileBatch::readCommit(const ObjectId& oid) {
    if (oid.isNull()) {
        return fail(GitError::Code::InvalidArgument, "Null object id");
    }
    auto object = read(oid.hex());
    if (!object) {
        return fail(std::move(object).error());
    }
    if (object->type != "commit") {
        return fail(GitError::Code::InvalidArgument,
                    "Object " + oid.shortHex() + " is a " + object->type + ", not a commit");
    }
    return CommitMeta::parseRawCommit(oid, object->content);
}

std::vector<CommitMeta> CatFileBatch::readCommits(const std::vector<ObjectId>& oids) {
    std::vector<CommitMeta> result;
    result.reserve(oids.size());
    for (const auto& oid : oids) {
        auto meta = readCommit(oid);
        if (meta) {
            result.push_back(std::move(*meta));
        }
        // A missing or unreadable object is skipped rather than fatal: history
        // browsing should survive a partially corrupt repository.
    }
    return result;
}

}  // namespace gbm
