#include "core/base/ThreadCheck.h"

#include "core/base/Logging.h"

#include <cstdio>
#include <cstdlib>

namespace gbm {

void reportUiThreadViolation(const char* function, const char* file, int line) {
    char buffer[512];
    std::snprintf(buffer,
                  sizeof(buffer),
                  "UI thread violation: %s() performs blocking work but was called on the UI "
                  "thread (%s:%d)",
                  function,
                  file,
                  line);
    logMessage(LogLevel::Error, buffer);
    std::fprintf(stderr, "%s\n", buffer);
    std::abort();
}

}  // namespace gbm
