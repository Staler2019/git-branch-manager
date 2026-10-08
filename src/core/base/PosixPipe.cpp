#include "core/base/PosixPipe.h"

#ifndef _WIN32

#include <fcntl.h>
#include <unistd.h>

namespace gbm::posix {

int makeCloexecPipe(int fds[2]) {
#if defined(__linux__)
    return ::pipe2(fds, O_CLOEXEC);
#else
    if (::pipe(fds) != 0) {
        return -1;
    }
    for (int i = 0; i < 2; ++i) {
        if (::fcntl(fds[i], F_SETFD, FD_CLOEXEC) != 0) {
            ::close(fds[0]);
            ::close(fds[1]);
            return -1;
        }
    }
    return 0;
#endif
}

int initSpawnAttr(posix_spawnattr_t* attr) {
    const int rc = ::posix_spawnattr_init(attr);
    if (rc != 0) {
        return rc;
    }
#if defined(__APPLE__)
    return ::posix_spawnattr_setflags(attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
#else
    return 0;
#endif
}

}  // namespace gbm::posix

#endif
