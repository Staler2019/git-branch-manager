#include "core/base/Logging.h"
#include "core/base/ThreadCheck.h"
#include "core/git/IProcessRunner.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#else
#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char** environ;
#endif

namespace gbm {

namespace {

constexpr std::size_t kReadBufferSize = 256 * 1024;

using Clock = std::chrono::steady_clock;

/// Splits a byte stream into records on a separator, invoking the sink for each
/// complete record. Deliberately hands out string_views into a reusable buffer:
/// at 500k commits a per-line std::string allocation is several hundred
/// milliseconds of pure overhead.
class LineSplitter {
public:
    LineSplitter(char separator, const LineSink& sink) : separator_(separator), sink_(sink) {}

    /// Returns false once the sink asks to stop.
    bool feed(std::string_view chunk) {
        pending_.append(chunk);
        std::size_t start = 0;
        for (;;) {
            const std::size_t end = pending_.find(separator_, start);
            if (end == std::string::npos) {
                break;
            }
            std::string_view record(pending_.data() + start, end - start);
            // Tolerate CRLF: git on Windows can emit \r\n even with --no-pager.
            if (separator_ == '\n' && !record.empty() && record.back() == '\r') {
                record.remove_suffix(1);
            }
            if (sink_ && !sink_(record)) {
                stopped_ = true;
                return false;
            }
            start = end + 1;
        }
        if (start > 0) {
            pending_.erase(0, start);
        }
        return true;
    }

    /// Emits any trailing record not terminated by a separator.
    void finish() {
        if (stopped_ || pending_.empty()) {
            return;
        }
        std::string_view record(pending_);
        if (separator_ == '\n' && !record.empty() && record.back() == '\r') {
            record.remove_suffix(1);
        }
        if (sink_) {
            sink_(record);
        }
        pending_.clear();
    }

private:
    char separator_;
    const LineSink& sink_;
    std::string pending_;
    bool stopped_ = false;
};

std::vector<std::string> buildArgv(const std::filesystem::path& exe, const GitCommand& command) {
    std::vector<std::string> argv;
    argv.reserve(command.args.size() + 8);
    argv.push_back(exe.string());
    for (auto& flag : GitCommand::globalFlags()) {
        argv.push_back(std::move(flag));
    }
    if (!command.repoDir.empty()) {
        argv.emplace_back("-C");
        argv.push_back(command.repoDir.string());
    }
    argv.insert(argv.end(), command.args.begin(), command.args.end());
    return argv;
}

#if !defined(_WIN32)

/// Ignores SIGPIPE exactly once per process. Without this, writing a patch to a
/// git process that has already exited kills the whole application.
void ignoreSigPipeOnce() {
    static std::once_flag flag;
    std::call_once(flag, [] { ::signal(SIGPIPE, SIG_IGN); });
}

class PosixChild {
public:
    ~PosixChild() { closeAll(); }

    GitResult<void> spawn(const std::vector<std::string>& argv,
                          const GitCommand& command,
                          bool wantStdin) {
        ignoreSigPipeOnce();

        int outPipe[2] = {-1, -1};
        int errPipe[2] = {-1, -1};
        int inPipe[2] = {-1, -1};
        if (::pipe(outPipe) != 0 || ::pipe(errPipe) != 0) {
            return fail(GitError::Code::SpawnFailed,
                        "Could not create a pipe for git",
                        std::strerror(errno));
        }
        if (wantStdin && ::pipe(inPipe) != 0) {
            ::close(outPipe[0]);
            ::close(outPipe[1]);
            ::close(errPipe[0]);
            ::close(errPipe[1]);
            return fail(GitError::Code::SpawnFailed,
                        "Could not create a pipe for git",
                        std::strerror(errno));
        }

        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
        posix_spawn_file_actions_adddup2(
            &actions, command.mergeStderrIntoStdout ? outPipe[1] : errPipe[1], STDERR_FILENO);
        if (wantStdin) {
            posix_spawn_file_actions_adddup2(&actions, inPipe[0], STDIN_FILENO);
        } else {
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
        }
        posix_spawn_file_actions_addclose(&actions, outPipe[0]);
        posix_spawn_file_actions_addclose(&actions, errPipe[0]);
        if (wantStdin) {
            posix_spawn_file_actions_addclose(&actions, inPipe[1]);
        }

        std::vector<char*> rawArgv;
        rawArgv.reserve(argv.size() + 1);
        for (const auto& arg : argv) {
            rawArgv.push_back(const_cast<char*>(arg.c_str()));
        }
        rawArgv.push_back(nullptr);

        const std::vector<std::string> envStrings = buildEnvironment(command);
        std::vector<char*> rawEnv;
        rawEnv.reserve(envStrings.size() + 1);
        for (const auto& entry : envStrings) {
            rawEnv.push_back(const_cast<char*>(entry.c_str()));
        }
        rawEnv.push_back(nullptr);

        // posix_spawn rather than fork+exec: fork() from a process that already
        // has a worker pool running is a well-known source of deadlocks in the
        // child between fork and exec.
        pid_t pid = -1;
        const int rc =
            ::posix_spawnp(&pid, rawArgv[0], &actions, nullptr, rawArgv.data(), rawEnv.data());
        posix_spawn_file_actions_destroy(&actions);

        ::close(outPipe[1]);
        ::close(errPipe[1]);
        if (wantStdin) {
            ::close(inPipe[0]);
        }

        if (rc != 0) {
            ::close(outPipe[0]);
            ::close(errPipe[0]);
            if (wantStdin) {
                ::close(inPipe[1]);
            }
            return fail(GitError::Code::SpawnFailed, "Could not start git", std::strerror(rc));
        }

        pid_.store(pid);
        stdoutFd_ = outPipe[0];
        stderrFd_ = errPipe[0];
        stdinFd_ = wantStdin ? inPipe[1] : -1;
        return {};
    }

    /// Pumps stdout, stderr and stdin until the child closes its pipes. A single
    /// poll() loop drains both output pipes, so a chatty stderr can never fill
    /// its buffer and deadlock a child that is still writing stdout.
    void pump(LineSplitter& stdoutSplitter,
              std::string* stderrText,
              const ProgressSink& onProgress,
              const std::string* stdinData,
              std::chrono::milliseconds timeout,
              bool* timedOut,
              bool* sinkStopped) {
        std::vector<char> buffer(kReadBufferSize);
        std::size_t stdinOffset = 0;
        const auto deadline = Clock::now() + timeout;

        while (stdoutFd_ >= 0 || stderrFd_ >= 0 || stdinFd_ >= 0) {
            struct pollfd fds[3];
            int count = 0;
            int stdoutIndex = -1;
            int stderrIndex = -1;
            int stdinIndex = -1;

            if (stdoutFd_ >= 0) {
                fds[count] = {stdoutFd_, POLLIN, 0};
                stdoutIndex = count++;
            }
            if (stderrFd_ >= 0) {
                fds[count] = {stderrFd_, POLLIN, 0};
                stderrIndex = count++;
            }
            if (stdinFd_ >= 0) {
                fds[count] = {stdinFd_, POLLOUT, 0};
                stdinIndex = count++;
            }

            int waitMs = 200;  // Bounded so cancellation is noticed promptly.
            if (timeout.count() > 0) {
                const auto remaining =
                    std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now())
                        .count();
                if (remaining <= 0) {
                    *timedOut = true;
                    terminate();
                    break;
                }
                waitMs = static_cast<int>(std::min<std::int64_t>(waitMs, remaining));
            }

            const int ready = ::poll(fds, static_cast<nfds_t>(count), waitMs);
            if (ready < 0) {
                if (errno == EINTR) {
                    continue;
                }
                break;
            }
            if (killed_.load()) {
                break;
            }
            if (ready == 0) {
                continue;
            }

            if (stdoutIndex >= 0 && (fds[stdoutIndex].revents & (POLLIN | POLLHUP)) != 0) {
                const ssize_t n = ::read(stdoutFd_, buffer.data(), buffer.size());
                if (n > 0) {
                    if (!stdoutSplitter.feed(
                            std::string_view(buffer.data(), static_cast<std::size_t>(n)))) {
                        *sinkStopped = true;
                        terminate();
                        break;
                    }
                } else if (n == 0 || (n < 0 && errno != EINTR && errno != EAGAIN)) {
                    ::close(stdoutFd_);
                    stdoutFd_ = -1;
                }
            }

            if (stderrIndex >= 0 && (fds[stderrIndex].revents & (POLLIN | POLLHUP)) != 0) {
                const ssize_t n = ::read(stderrFd_, buffer.data(), buffer.size());
                if (n > 0) {
                    const std::string_view chunk(buffer.data(), static_cast<std::size_t>(n));
                    if (stderrText != nullptr) {
                        stderrText->append(chunk);
                    }
                    if (onProgress) {
                        onProgress(chunk);
                    }
                } else if (n == 0 || (n < 0 && errno != EINTR && errno != EAGAIN)) {
                    ::close(stderrFd_);
                    stderrFd_ = -1;
                }
            }

            if (stdinIndex >= 0 && (fds[stdinIndex].revents & (POLLOUT | POLLERR | POLLHUP)) != 0) {
                if (stdinData == nullptr || stdinOffset >= stdinData->size()) {
                    ::close(stdinFd_);
                    stdinFd_ = -1;
                } else {
                    const ssize_t n = ::write(
                        stdinFd_, stdinData->data() + stdinOffset, stdinData->size() - stdinOffset);
                    if (n > 0) {
                        stdinOffset += static_cast<std::size_t>(n);
                    } else if (n < 0 && errno != EINTR && errno != EAGAIN) {
                        ::close(stdinFd_);
                        stdinFd_ = -1;
                    }
                    if (stdinData != nullptr && stdinOffset >= stdinData->size() && stdinFd_ >= 0) {
                        ::close(stdinFd_);
                        stdinFd_ = -1;
                    }
                }
            }
        }
        stdoutSplitter.finish();
    }

    int wait() {
        const pid_t pid = pid_.load();
        if (pid <= 0) {
            return -1;
        }
        int status = 0;
        while (::waitpid(pid, &status, 0) < 0) {
            if (errno != EINTR) {
                return -1;
            }
        }
        pid_.store(-1);
        if (WIFEXITED(status)) {
            return WEXITSTATUS(status);
        }
        if (WIFSIGNALED(status)) {
            return 128 + WTERMSIG(status);
        }
        return -1;
    }

    /// SIGTERM, then SIGKILL if the child does not go away. Only ever used for
    /// read-only commands: a mutating git process is never killed mid-flight.
    void terminate() {
        const pid_t pid = pid_.load();
        if (pid <= 0) {
            return;
        }
        killed_.store(true);
        ::kill(pid, SIGTERM);

        for (int i = 0; i < 30; ++i) {
            int status = 0;
            const pid_t result = ::waitpid(pid, &status, WNOHANG);
            if (result == pid || (result < 0 && errno == ECHILD)) {
                pid_.store(-1);
                return;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        ::kill(pid, SIGKILL);
    }

private:
    static std::vector<std::string> buildEnvironment(const GitCommand& command) {
        std::vector<std::string> entries;
        for (char** env = environ; env != nullptr && *env != nullptr; ++env) {
            entries.emplace_back(*env);
        }
        auto setVar = [&entries](const std::string& key, const std::string& value) {
            const std::string prefix = key + "=";
            for (auto& entry : entries) {
                if (entry.rfind(prefix, 0) == 0) {
                    entry = prefix + value;
                    return;
                }
            }
            entries.push_back(prefix + value);
        };
        // No terminal exists, so a credential prompt would hang the child
        // forever. Disabling it converts that hang into a reportable auth error.
        setVar("GIT_TERMINAL_PROMPT", "0");
        setVar("GIT_PAGER", "cat");
        setVar("LC_ALL", "C");
        for (const auto& [key, value] : command.envOverrides) {
            setVar(key, value);
        }
        return entries;
    }

    void closeAll() {
        if (stdoutFd_ >= 0) ::close(stdoutFd_);
        if (stderrFd_ >= 0) ::close(stderrFd_);
        if (stdinFd_ >= 0) ::close(stdinFd_);
        stdoutFd_ = stderrFd_ = stdinFd_ = -1;
    }

    std::atomic<pid_t> pid_{-1};
    std::atomic_bool killed_{false};
    int stdoutFd_ = -1;
    int stderrFd_ = -1;
    int stdinFd_ = -1;
};

using PlatformChild = PosixChild;

#else  // _WIN32

/// Quotes an argument per the CommandLineToArgvW rules that CreateProcessW
/// consumers use. Windows has no argv array at the API level, so this conversion
/// is unavoidable — but it happens in exactly one place, and never involves a
/// shell.
std::wstring quoteArgument(const std::wstring& arg) {
    if (!arg.empty() && arg.find_first_of(L" \t\n\v\"") == std::wstring::npos) {
        return arg;
    }
    std::wstring quoted;
    quoted.push_back(L'"');
    for (auto it = arg.begin();; ++it) {
        unsigned backslashes = 0;
        while (it != arg.end() && *it == L'\\') {
            ++it;
            ++backslashes;
        }
        if (it == arg.end()) {
            quoted.append(backslashes * 2, L'\\');
            break;
        }
        if (*it == L'"') {
            quoted.append(backslashes * 2 + 1, L'\\');
        } else {
            quoted.append(backslashes, L'\\');
        }
        quoted.push_back(*it);
    }
    quoted.push_back(L'"');
    return quoted;
}

std::wstring widen(const std::string& utf8) {
    if (utf8.empty()) {
        return {};
    }
    const int needed =
        ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring wide(static_cast<std::size_t>(needed), L'\0');
    ::MultiByteToWideChar(
        CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), wide.data(), needed);
    return wide;
}

class WindowsChild {
public:
    ~WindowsChild() { closeAll(); }

    GitResult<void> spawn(const std::vector<std::string>& argv,
                          const GitCommand& command,
                          bool wantStdin) {
        SECURITY_ATTRIBUTES sa{};
        sa.nLength = sizeof(sa);
        sa.bInheritHandle = TRUE;

        HANDLE outRead = nullptr;
        HANDLE outWrite = nullptr;
        HANDLE errRead = nullptr;
        HANDLE errWrite = nullptr;
        HANDLE inRead = nullptr;
        HANDLE inWrite = nullptr;

        if (!::CreatePipe(&outRead, &outWrite, &sa, 0) ||
            !::CreatePipe(&errRead, &errWrite, &sa, 0)) {
            return fail(GitError::Code::SpawnFailed, "Could not create a pipe for git");
        }
        if (wantStdin && !::CreatePipe(&inRead, &inWrite, &sa, 0)) {
            return fail(GitError::Code::SpawnFailed, "Could not create a pipe for git");
        }
        ::SetHandleInformation(outRead, HANDLE_FLAG_INHERIT, 0);
        ::SetHandleInformation(errRead, HANDLE_FLAG_INHERIT, 0);
        if (wantStdin) {
            ::SetHandleInformation(inWrite, HANDLE_FLAG_INHERIT, 0);
        }

        std::wstring commandLine;
        for (std::size_t i = 0; i < argv.size(); ++i) {
            if (i != 0) {
                commandLine.push_back(L' ');
            }
            commandLine += quoteArgument(widen(argv[i]));
        }

        STARTUPINFOW si{};
        si.cb = sizeof(si);
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdOutput = outWrite;
        si.hStdError = command.mergeStderrIntoStdout ? outWrite : errWrite;
        si.hStdInput = wantStdin ? inRead : ::GetStdHandle(STD_INPUT_HANDLE);

        DWORD flags = CREATE_UNICODE_ENVIRONMENT;
        if (command.noWindow) {
            // Without this a console window flashes on every git invocation.
            flags |= CREATE_NO_WINDOW;
        }

        std::wstring environment = buildEnvironmentBlock(command);
        PROCESS_INFORMATION pi{};
        std::vector<wchar_t> mutableCommandLine(commandLine.begin(), commandLine.end());
        mutableCommandLine.push_back(L'\0');

        const BOOL ok = ::CreateProcessW(nullptr,
                                         mutableCommandLine.data(),
                                         nullptr,
                                         nullptr,
                                         TRUE,
                                         flags,
                                         environment.data(),
                                         nullptr,
                                         &si,
                                         &pi);

        ::CloseHandle(outWrite);
        ::CloseHandle(errWrite);
        if (wantStdin) {
            ::CloseHandle(inRead);
        }

        if (!ok) {
            ::CloseHandle(outRead);
            ::CloseHandle(errRead);
            if (wantStdin) {
                ::CloseHandle(inWrite);
            }
            return fail(GitError::Code::SpawnFailed,
                        "Could not start git",
                        "CreateProcessW failed with " + std::to_string(::GetLastError()));
        }

        ::CloseHandle(pi.hThread);
        process_ = pi.hProcess;
        stdoutHandle_ = outRead;
        stderrHandle_ = errRead;
        stdinHandle_ = wantStdin ? inWrite : nullptr;
        return {};
    }

    /// stdout is read on this thread with blocking reads so bulk output runs at
    /// full speed; stderr (low volume) and stdin get helper threads. Draining
    /// all three concurrently is what prevents a full-pipe deadlock.
    void pump(LineSplitter& stdoutSplitter,
              std::string* stderrText,
              const ProgressSink& onProgress,
              const std::string* stdinData,
              std::chrono::milliseconds timeout,
              bool* timedOut,
              bool* sinkStopped) {
        std::thread stderrThread;
        if (stderrHandle_ != nullptr) {
            stderrThread = std::thread([this, stderrText, &onProgress] {
                std::vector<char> buffer(16 * 1024);
                for (;;) {
                    DWORD read = 0;
                    if (!::ReadFile(stderrHandle_,
                                    buffer.data(),
                                    static_cast<DWORD>(buffer.size()),
                                    &read,
                                    nullptr) ||
                        read == 0) {
                        return;
                    }
                    const std::string_view chunk(buffer.data(), read);
                    std::lock_guard<std::mutex> lock(stderrMutex_);
                    if (stderrText != nullptr) {
                        stderrText->append(chunk);
                    }
                    if (onProgress) {
                        onProgress(chunk);
                    }
                }
            });
        }

        std::thread stdinThread;
        if (stdinHandle_ != nullptr) {
            stdinThread = std::thread([this, stdinData] {
                if (stdinData != nullptr) {
                    std::size_t offset = 0;
                    while (offset < stdinData->size()) {
                        DWORD written = 0;
                        if (!::WriteFile(stdinHandle_,
                                         stdinData->data() + offset,
                                         static_cast<DWORD>(stdinData->size() - offset),
                                         &written,
                                         nullptr) ||
                            written == 0) {
                            break;
                        }
                        offset += written;
                    }
                }
                ::CloseHandle(stdinHandle_);
                stdinHandle_ = nullptr;
            });
        }

        std::vector<char> buffer(kReadBufferSize);
        const auto deadline = Clock::now() + timeout;
        for (;;) {
            if (timeout.count() > 0 && Clock::now() > deadline) {
                *timedOut = true;
                terminate();
                break;
            }
            DWORD read = 0;
            if (!::ReadFile(stdoutHandle_,
                            buffer.data(),
                            static_cast<DWORD>(buffer.size()),
                            &read,
                            nullptr) ||
                read == 0) {
                break;
            }
            if (!stdoutSplitter.feed(std::string_view(buffer.data(), read))) {
                *sinkStopped = true;
                terminate();
                break;
            }
        }
        stdoutSplitter.finish();

        if (stderrThread.joinable()) {
            stderrThread.join();
        }
        if (stdinThread.joinable()) {
            stdinThread.join();
        }
    }

    int wait() {
        if (process_ == nullptr) {
            return -1;
        }
        ::WaitForSingleObject(process_, INFINITE);
        DWORD code = 0;
        ::GetExitCodeProcess(process_, &code);
        return static_cast<int>(code);
    }

    void terminate() {
        if (process_ != nullptr) {
            ::TerminateProcess(process_, 1);
        }
    }

private:
    static std::wstring buildEnvironmentBlock(const GitCommand& command) {
        std::vector<std::pair<std::wstring, std::wstring>> overrides;
        overrides.emplace_back(L"GIT_TERMINAL_PROMPT", L"0");
        overrides.emplace_back(L"GIT_PAGER", L"cat");
        overrides.emplace_back(L"LC_ALL", L"C");
        for (const auto& [key, value] : command.envOverrides) {
            overrides.emplace_back(widen(key), widen(value));
        }

        std::wstring block;
        LPWCH existing = ::GetEnvironmentStringsW();
        if (existing != nullptr) {
            for (LPWCH cursor = existing; *cursor != L'\0';) {
                const std::wstring entry(cursor);
                cursor += entry.size() + 1;
                const std::size_t eq = entry.find(L'=');
                if (eq != std::wstring::npos) {
                    const std::wstring key = entry.substr(0, eq);
                    const bool overridden =
                        std::any_of(overrides.begin(), overrides.end(), [&key](const auto& kv) {
                            return ::_wcsicmp(kv.first.c_str(), key.c_str()) == 0;
                        });
                    if (overridden) {
                        continue;
                    }
                }
                block += entry;
                block.push_back(L'\0');
            }
            ::FreeEnvironmentStringsW(existing);
        }
        for (const auto& [key, value] : overrides) {
            block += key + L"=" + value;
            block.push_back(L'\0');
        }
        block.push_back(L'\0');
        return block;
    }

    void closeAll() {
        if (stdoutHandle_ != nullptr) ::CloseHandle(stdoutHandle_);
        if (stderrHandle_ != nullptr) ::CloseHandle(stderrHandle_);
        if (stdinHandle_ != nullptr) ::CloseHandle(stdinHandle_);
        if (process_ != nullptr) ::CloseHandle(process_);
        stdoutHandle_ = stderrHandle_ = stdinHandle_ = process_ = nullptr;
    }

    HANDLE process_ = nullptr;
    HANDLE stdoutHandle_ = nullptr;
    HANDLE stderrHandle_ = nullptr;
    HANDLE stdinHandle_ = nullptr;
    std::mutex stderrMutex_;
};

using PlatformChild = WindowsChild;

#endif

class ProcessRunner final : public IProcessRunner {
public:
    explicit ProcessRunner(std::filesystem::path gitExecutable) : git_(std::move(gitExecutable)) {}

    GitResult<ProcessResult> run(const GitCommand& command, CancellationToken token) override {
        std::string output;
        const LineSink sink = [&output](std::string_view line) {
            output.append(line);
            output.push_back('\n');
            return true;
        };
        auto result = execute(command, '\n', sink, nullptr, token, &output);
        if (result) {
            // Trim the trailing separator the sink added for the final record.
            if (!output.empty() && output.back() == '\n') {
                output.pop_back();
            }
            result->out = std::move(output);
        }
        return result;
    }

    GitResult<ProcessResult> stream(const GitCommand& command,
                                    const LineSink& onLine,
                                    const ProgressSink& onProgress,
                                    CancellationToken token) override {
        return execute(command, '\n', onLine, onProgress, token, nullptr);
    }

    GitResult<ProcessResult> streamSeparated(const GitCommand& command,
                                             Separator separator,
                                             const LineSink& onLine,
                                             const ProgressSink& onProgress,
                                             CancellationToken token) override {
        return execute(
            command, separator == Separator::Nul ? '\0' : '\n', onLine, onProgress, token, nullptr);
    }

private:
    /// `capturedStdout`, when provided, lets the failure path look at stdout as
    /// well as stderr — see the classification note below.
    GitResult<ProcessResult> execute(const GitCommand& command,
                                     char separator,
                                     const LineSink& onLine,
                                     const ProgressSink& onProgress,
                                     CancellationToken token,
                                     const std::string* capturedStdout) {
        // Spawning a process and blocking on its output is precisely what must
        // never happen on the UI thread.
        GBM_ASSERT_NOT_UI_THREAD();

        const auto argv = buildArgv(git_, command);
        const auto started = Clock::now();

        if (token.isCancelled()) {
            return cancelled();
        }

        auto child = std::make_shared<PlatformChild>();
        if (auto spawned = child->spawn(argv, command, command.stdinData.has_value()); !spawned) {
            GitError error = std::move(spawned).error();
            error.argv = argv;
            recordOperation(command, argv, error.detail, -1, started, false, false);
            return fail(std::move(error));
        }

        // Cancelling closes the child down. Registered after a successful spawn
        // so there is no window in which we could signal a pid we do not own.
        //
        // `cancelObserved` is a shared_ptr, not a stack local captured by
        // reference: without the Registration below, a cancel firing after
        // this function had already returned (readCancel_ was only replaced
        // on the next explicit cancelPendingReads(), so a session could
        // accumulate one registered callback per git process for its whole
        // lifetime, and cancelPendingReads() fired all of them at once on
        // repo switch) wrote into a long-dead stack frame. `cancelReg`
        // unregisters the callback on every return path below, and the
        // shared_ptr is belt-and-braces against any callback that is already
        // mid-fire when that happens.
        auto cancelObserved = std::make_shared<std::atomic_bool>(false);
        CancellationToken::Registration cancelReg = token.onCancel([child, cancelObserved] {
            cancelObserved->store(true);
            child->terminate();
        });

        ProcessResult result;
        LineSplitter splitter(separator, onLine);
        bool sinkStopped = false;
        child->pump(splitter,
                    &result.err,
                    onProgress,
                    command.stdinData ? &*command.stdinData : nullptr,
                    command.timeout,
                    &result.timedOut,
                    &sinkStopped);

        result.exitCode = child->wait();
        result.duration =
            std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - started);
        result.cancelled = cancelObserved->load() || token.isCancelled();

        // The child has been waited on (reaped) by this point, and every
        // path below only reports the result -- nothing past here needs the
        // callback to stay registered, so unregister it now rather than
        // leaving it live until the caller's CancellationSource is
        // eventually replaced or destroyed.
        cancelReg.reset();

        recordOperation(
            command, argv, result.err, result.exitCode, started, result.cancelled, result.timedOut);

        if (result.cancelled) {
            return cancelled();
        }
        if (result.timedOut) {
            GitError error(GitError::Code::Timeout, "Git did not finish in time", result.err);
            error.argv = argv;
            return fail(std::move(error));
        }
        // A sink that asked to stop early leaves a non-zero exit code behind
        // because we killed the child; that is success from the caller's view.
        if (result.exitCode != 0 && !sinkStopped) {
            GitError error = classifyGitStderr(result.err, result.exitCode);

            // git writes several important outcomes to *stdout*, not stderr -- most
            // notably "CONFLICT (content): ..." from merge, cherry-pick and rebase.
            // Classifying on stderr alone would report those as a generic failure,
            // and the UI would miss the chance to open the conflict view.
            if (error.code == GitError::Code::ProcessFailed && capturedStdout != nullptr &&
                !capturedStdout->empty()) {
                GitError fromStdout = classifyGitStderr(*capturedStdout, result.exitCode);
                if (fromStdout.code != GitError::Code::ProcessFailed) {
                    error.code = fromStdout.code;
                    error.message = fromStdout.message;
                    // Keep both streams: the operation log must show everything git said.
                    error.detail =
                        result.err.empty() ? *capturedStdout : result.err + "\n" + *capturedStdout;
                }
            }

            error.argv = argv;
            return fail(std::move(error));
        }
        return result;
    }

    static void recordOperation(const GitCommand& command,
                                const std::vector<std::string>& argv,
                                const std::string& stderrText,
                                int exitCode,
                                Clock::time_point started,
                                bool wasCancelled,
                                bool wasTimeout) {
        OperationRecord record;
        record.when = std::chrono::system_clock::now();
        record.repoDir = command.repoDir.string();
        record.argv = argv;
        record.exitCode = exitCode;
        record.durationMs =
            std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - started).count();
        record.stderrText = stderrText;
        record.cancelled = wasCancelled;
        record.timedOut = wasTimeout;
        Log::instance().recordOperation(record);
    }

    std::filesystem::path git_;
};

}  // namespace

std::unique_ptr<IProcessRunner> makeProcessRunner(std::filesystem::path gitExecutable) {
    return std::make_unique<ProcessRunner>(std::move(gitExecutable));
}

}  // namespace gbm
