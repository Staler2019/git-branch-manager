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
//   --drip N    Print N lines `kDripIntervalMs` apart, then fall silent
//               forever. This is the one that tells an *idle* deadline apart
//               from a *total-duration* one: a total-duration deadline kills
//               this child while it is still producing, an idle deadline lets
//               it run and only fires once it goes quiet. Without this mode,
//               implementing "idle" as "total" passes every test.
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

namespace {
constexpr int kDripIntervalMs = 200;
}

int main(int argc, char** argv) {
    int dripLines = 0;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--drip") == 0 && i + 1 < argc) {
            dripLines = std::atoi(argv[i + 1]);
            break;
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
