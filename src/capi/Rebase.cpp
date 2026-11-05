#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/base/ObjectId.h"
#include "core/git/ops/RebaseOps.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_rebase_plan(GbmSessionHandle session, const char* upstream) try {
    toSession(session)->requestRebasePlan(upstream != nullptr ? upstream : "");
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_rebase_interactive_start(GbmSessionHandle session,
                                          const char* upstream,
                                          const char* onto,
                                          const int32_t* actions,
                                          const char* const* oids,
                                          const char* const* subjects,
                                          int32_t entryCount,
                                          int32_t stashFirst) try {
    RebaseInteractiveRequest request;
    request.upstream = upstream != nullptr ? upstream : "";
    request.onto = onto != nullptr ? onto : "";
    request.stashFirst = stashFirst != 0;
    request.todo.reserve(static_cast<std::size_t>(entryCount > 0 ? entryCount : 0));
    for (int32_t i = 0; i < entryCount; ++i) {
        RebaseTodoEntry entry;
        entry.action = static_cast<RebaseTodoEntry::Action>(actions[i]);
        entry.oid = oids[i] != nullptr ? ObjectId::fromHex(oids[i]) : ObjectId{};
        entry.subject = subjects[i] != nullptr ? subjects[i] : "";
        request.todo.push_back(std::move(entry));
    }
    toSession(session)->startInteractiveRebase(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_rebase_start(GbmSessionHandle session,
                              const char* upstream,
                              const char* onto,
                              int32_t stashFirst,
                              int32_t rebaseMerges,
                              int32_t autosquash) try {
    RebaseRequest request;
    request.upstream = upstream != nullptr ? upstream : "";
    request.onto = onto != nullptr ? onto : "";
    request.stashFirst = stashFirst != 0;
    request.rebaseMerges = rebaseMerges != 0;
    request.autosquash = autosquash != 0;
    toSession(session)->startRebase(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_rebase_continue(GbmSessionHandle session) try {
    toSession(session)->continueRebase();
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_rebase_continue_with_message(GbmSessionHandle session, const char* message) try {
    toSession(session)->continueRebaseWithMessage(message != nullptr ? std::string(message) : "");
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_rebase_skip(GbmSessionHandle session) try {
    toSession(session)->skipRebase();
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_rebase_abort(GbmSessionHandle session) try {
    toSession(session)->abortRebase();
} catch (...) {
    reportNativeException(__func__);
}
