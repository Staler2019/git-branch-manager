// A child that writes nothing and never exits on its own.
//
// It exists because `GitCommand::timeout` had no test on either platform --
// every `.timeout` in the suite is a 30-120 second value that never fires -- and
// the Windows pump can only check its deadline *between* two `ReadFile` calls.
// A child that never writes therefore leaves the pump blocked in a synchronous
// read that nothing interrupts, so the deadline is never reached at all. git
// itself cannot play this part: with no stdin pipe the child gets EOF
// immediately, so `cat-file --batch` and friends exit rather than hang, and
// anything network-shaped drags ports into a unit test.
//
// Deliberately silent: writing even one byte would let the Windows read return
// and the deadline check at the top of the loop would fire, which is the very
// path that already worked. The defect only exists while the pipe stays empty.
//
// It must die to being killed, and does: SIGTERM's default disposition on
// POSIX, and `TerminateJobObject`/`TerminateProcess` on Windows. argv is
// ignored, because the runner prepends git's own global flags to it.
#include <chrono>
#include <thread>

int main() {
    for (;;) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}
