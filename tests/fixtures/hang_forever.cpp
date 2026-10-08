// A child that never exits on its own, and either says nothing or drips.
//
// It exists because `GitCommand`'s deadlines had no test on either platform --
// every `.timeout` in the suite is a 30-120 second value that never fires -- and
// the Windows pump can only check a deadline *between* two `ReadFile` calls. A
// child that never writes therefore leaves the pump blocked in a synchronous
// read that nothing interrupts, so the deadline is never reached at all. git
// itself cannot play this part: with no stdin pipe the child gets EOF
// immediately, so `cat-file --batch` and friends exit rather than hang, and
// anything network-shaped drags ports into a unit test.
//
// It must die to being killed, and does: SIGTERM's default disposition on
// POSIX, and `TerminateJobObject`/`TerminateProcess` on Windows.
//
// Two modes:
//
//   (default)   Silent forever. Deliberately not one byte: writing anything
//               would let the Windows read return, and the deadline check at
//               the top of the loop -- the path that already worked -- would
//               fire. The defect only exists while the pipe stays empty.
//
//   --drip-stderr N
//               The same, on stderr and in git's `--progress` shape: each
//               update rewrites one line with '\r' and only the last ends in
//               '\n'. It is how a network command shows it is alive, and the
//               Windows pump reads stderr on its own thread, so this is the
//               mode that proves that thread counts as progress there.
//
//   --drip N    Print N lines `kDripIntervalMs` apart, then fall silent
//               forever. This is the one that tells an *idle* deadline apart
//               from a *total-duration* one: a total-duration deadline kills
//               this child while it is still producing, an idle deadline lets
//               it run and only fires once it goes quiet. Without this mode,
//               implementing "idle" as "total" passes every test.
//
//   --detach-grandchild   (POSIX only)
//               Fork a grandchild that points its own 0/1/2 at /dev/null and
//               sleeps kGrandchildSeconds, then exit 0 at once. It is
//               `git fsmonitor--daemon` in miniature: a long-lived process
//               spawned by the child that never writes to the pipe, yet holds
//               every *other* fd it inherited. If the runner leaked its pipe's
//               write end into the child under its original fd number, the
//               grandchild keeps that pipe open and the run never sees EOF.
//
// **Every line is flushed.** stdout to a pipe is block-buffered, so an
// unflushed drip would sit in this process's buffer and reach the parent as
// one burst at exit -- indistinguishable from silence, and the drip test would
// then pass for entirely the wrong reason.
//
// **argv is scanned, not indexed.** `buildArgv()` puts the executable first,
// then `GitCommand::globalFlags()`, then an optional `-C <dir>`, and only then
// the caller's own args -- so the flag's position is not fixed. (An earlier
// version of this comment said argv was ignored; that stopped being true when
// `--drip` was added, and is corrected here rather than left to mislead.)
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>

#ifndef _WIN32
#include <fcntl.h>
#include <unistd.h>
#endif

namespace {
constexpr int kDripIntervalMs = 200;
constexpr int kGrandchildSeconds = 5;
}  // namespace

int main(int argc, char** argv) {
#ifndef _WIN32
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--detach-grandchild") != 0) {
            continue;
        }
        if (::fork() == 0) {
            const int devNull = ::open("/dev/null", O_RDWR);
            ::dup2(devNull, STDIN_FILENO);
            ::dup2(devNull, STDOUT_FILENO);
            ::dup2(devNull, STDERR_FILENO);
            ::sleep(kGrandchildSeconds);
            ::_exit(0);
        }
        return 0;
    }
#endif

    int dripLines = 0;
    bool toStderr = false;
    for (int i = 1; i < argc; ++i) {
        if ((std::strcmp(argv[i], "--drip") == 0 || std::strcmp(argv[i], "--drip-stderr") == 0) &&
            i + 1 < argc) {
            toStderr = std::strcmp(argv[i], "--drip-stderr") == 0;
            dripLines = std::atoi(argv[i + 1]);
            break;
        }
    }

    if (toStderr) {
        for (int i = 0; i < dripLines; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(kDripIntervalMs));
            std::fprintf(stderr, "Receiving objects: %3d%%%s", (i + 1) * 100 / dripLines,
                         i + 1 == dripLines ? "\n" : "\r");
            std::fflush(stderr);
        }
        for (;;) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }

    for (int i = 0; i < dripLines; ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(kDripIntervalMs));
        std::printf("drip %d\n", i);
        std::fflush(stdout);
    }

    for (;;) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}
