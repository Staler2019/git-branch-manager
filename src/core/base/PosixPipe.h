#pragma once

#ifndef _WIN32

#include <spawn.h>

namespace gbm::posix {

/// `::pipe()` with both ends close-on-exec, same contract (0 on success, -1
/// and errno on failure).
///
/// **Why it must be close-on-exec.** `posix_spawn`'s `adddup2` puts a pipe
/// end on 0/1/2 in the child, but the original fd number stays open there too
/// unless it is close-on-exec. A grandchild that redirects its own 0/1/2 --
/// `git fsmonitor--daemon`, started by `git worktree add` -- then still holds
/// the write end, and the parent's read loop never sees EOF: the operation
/// stays "running" long after git has exited. `dup2` clears the flag on the
/// target, so 0/1/2 still reach the child.
int makeCloexecPipe(int fds[2]);

/// `posix_spawnattr_init`, plus `POSIX_SPAWN_CLOEXEC_DEFAULT` on Apple: the
/// child gets only the fds its file actions name. That also closes the gap
/// `makeCloexecPipe` leaves where `pipe2` is unavailable -- another thread
/// spawning between `pipe()` and `fcntl()` would inherit the new pipe.
/// Returns 0 on success; the caller destroys the attr either way it is used.
int initSpawnAttr(posix_spawnattr_t* attr);

}  // namespace gbm::posix

#endif
