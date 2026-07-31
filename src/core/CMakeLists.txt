# The core library deliberately links NO Qt target. Every data-layer decision is
# testable from a plain GoogleTest binary with no QApplication, and CI enforces
# the boundary by grepping this directory for Qt includes.
add_library(gbm_core STATIC
    base/Error.cpp
    base/FsUtil.cpp
    base/Logging.cpp
    base/ThreadCheck.cpp

    git/CatFileBatch.cpp
    git/CommitMeta.cpp
    git/DiffService.cpp
    git/GitExecutable.cpp
    git/HistoryProvider.cpp
    git/OperationRunner.cpp
    git/ProcessRunner.cpp
    git/RefStore.cpp
    git/RepoState.cpp
    git/SideBySideDiff.cpp
    git/UnifiedDiffParser.cpp
    git/WorkingCopyStatus.cpp
    git/ops/BranchOps.cpp
    git/ops/CheckoutOp.cpp
    git/ops/CherryPickOps.cpp
    git/ops/CommitOps.cpp
    git/ops/ConflictOps.cpp
    git/ops/MergeOps.cpp
    git/ops/StageOps.cpp

    graph/GraphAsciiRenderer.cpp
    graph/GraphBuilder.cpp
    graph/GraphSnapshot.cpp

    discovery/RepoClassifier.cpp
    discovery/Scanner.cpp
    discovery/SkipRules.cpp

    cache/Database.cpp
    cache/RepoIndexDb.cpp

    workers/ThreadPool.cpp
)

target_include_directories(gbm_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../")

target_link_libraries(gbm_core
    PUBLIC gbm_sqlite3
    PRIVATE gbm_warnings gbm_sanitizers)

if(NOT WIN32)
    find_package(Threads REQUIRED)
    target_link_libraries(gbm_core PUBLIC Threads::Threads)
endif()

# Thread checks abort on a UI-thread violation. On in debug and test builds; off
# in release so a latent mistake degrades performance instead of killing a
# user's session mid-operation.
target_compile_definitions(gbm_core PUBLIC
    $<$<CONFIG:Debug,RelWithDebInfo>:GBM_ENABLE_THREAD_CHECKS>)
