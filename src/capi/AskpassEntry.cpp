#include "capi/gbm_capi.h"
#include "core/git/AskpassHelper.h"

#include <cstdlib>
#include <cstring>

// See gbm_capi.h. A thin bridge: the protocol is core's askpass::runClient().
// The mode check is ASCII, so the narrow getenv() is exact on every platform;
// the request directory, which may not be, is read wide inside runClient().
GBM_API int32_t gbm_askpass_main(int32_t argc, const char* const* argv) {
    const char* mode = std::getenv("GBM_ASKPASS_MODE");
    if (mode == nullptr || std::strcmp(mode, "1") != 0) {
        return -1;
    }
    return gbm::askpass::runClient(argc, argv);
}
