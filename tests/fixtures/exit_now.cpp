// A child that writes one known line and exits 0, as fast as it can.
//
// It is the *subject* of the job-object A/B measurement (tools/spawn_cost_win.cpp):
// the thing being timed there is the spawn, not the work, so the child has to
// do as close to nothing as a real process can. `git --version` is the cheapest
// real git invocation and is used as that measurement's denominator -- but it
// is not usable as the subject, because git's own startup swamps the
// microsecond-scale difference the A/B is looking for.
//
// It writes rather than exiting silently for one reason: the measuring side
// asserts on the exact bytes. A spawn that *failed* is very fast, and a failed
// spawn counted as a sample would show up as the job-object arm being free or
// even cheaper than no job at all. Checking the payload is what makes that
// impossible to mistake for a result.
//
// **stdout is put into binary mode on Windows**, and that is load-bearing
// rather than tidiness. The Windows CRT opens stdout in *text* mode, which
// translates the `\n` below into `\r\n` on the way into the pipe -- so the
// measuring side, which compares the raw `ReadFile` bytes against `"ok\n"`,
// would fail its own payload assertion on every single sample and the tool
// would report `a spawn failed mid-loop` on iteration 1. Fixing it here keeps
// the assertion exact; loosening the comparison to accept either ending would
// have thrown away the one check that tells a failed spawn from a fast one.
#include <cstdio>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

int main() {
#ifdef _WIN32
    ::_setmode(::_fileno(stdout), _O_BINARY);
#endif
    std::fputs("ok\n", stdout);
    return 0;
}
