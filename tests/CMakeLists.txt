include(GoogleTest)

# Test doubles live here rather than in the shipped library.
add_library(gbm_test_support STATIC support/FakeProcessRunner.cpp support/GitCli.cpp)
target_include_directories(gbm_test_support PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(gbm_test_support PUBLIC gbm_core PRIVATE gbm_warnings)

# --- core unit + integration tests -------------------------------------
add_executable(gbm_core_tests
    unit/BranchOpsTest.cpp
    unit/CompareOpsTest.cpp
    unit/ConflictBatchTest.cpp
    unit/ConflictMarkerParserTest.cpp
    unit/CoreBasicsTest.cpp
    unit/DelayTimerTest.cpp
    unit/DiscoveryTest.cpp
    unit/GitCliTest.cpp
    unit/GitExecutableTest.cpp
    unit/GitIntegrationTest.cpp
    unit/GraphBuilderTest.cpp
    unit/InitCloneOpsTest.cpp
    unit/MaintenanceOpsTest.cpp
    unit/OriginalOperationMessageTest.cpp
    unit/PreparedCommitMessageTest.cpp
    unit/ProcessRunnerTest.cpp
    unit/RefStoreHeadTest.cpp
    unit/RemoteOpsTest.cpp
    unit/RepoStateTest.cpp
    unit/SideBySideDiffTest.cpp
    unit/WorktreeCreatedAtTest.cpp
    unit/WorktreePendingCountTest.cpp
    unit/WorktreeReadFlagsTest.cpp
    unit/TextTraitsTest.cpp
    unit/UnifiedDiffParserTest.cpp
)
target_link_libraries(gbm_core_tests
    PRIVATE gbm_core gbm_test_support GTest::gtest GTest::gtest_main gbm_warnings
            gbm_sanitizers)

# Labels let CI gate on the fast suites and run perf separately: runners are far
# too noisy for timing assertions to gate a pull request.
gtest_discover_tests(gbm_core_tests
    PROPERTIES LABELS "unit"
    DISCOVERY_TIMEOUT 60)

# --- history fixture generator ---------------------------------------------
# Not a test: it emits a `git fast-import` stream. Building 200k commits with
# `git commit` would take hours and need a working tree; fast-import does it in
# seconds with neither.
add_executable(gen_history fixtures/gen_history.cpp)
target_link_libraries(gen_history PRIVATE gbm_warnings)

# --- end-to-end check against a generated repository -----------------------
# Runs the generator, imports it with real git, writes a commit-graph, then walks
# the result and compares our row order with git's own.
find_package(Git QUIET)
if(GIT_FOUND)
    add_test(NAME graph_matches_git_on_generated_history
        COMMAND "${CMAKE_COMMAND}"
                -DGIT_EXECUTABLE=${GIT_EXECUTABLE}
                -DGEN_HISTORY=$<TARGET_FILE:gen_history>
                -DWALKER=$<TARGET_FILE:gbm_graph_check>
                -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/fixture-repo
                -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunFixtureCheck.cmake")
    set_tests_properties(graph_matches_git_on_generated_history
        PROPERTIES LABELS "integration" TIMEOUT 600)
endif()

# A small driver used by the test above and for manual profiling.
add_executable(gbm_graph_check tools/graph_check.cpp)
target_link_libraries(gbm_graph_check PRIVATE gbm_core gbm_warnings)

# --- nightly commit-graph speedup gate --------------------------------------
# Not a pull-request gate: it builds a ${GBM_PERF_COMMITS}-commit fixture and
# then times things, and a shared CI runner is far too noisy for timing to
# gate somebody's branch (see the label comment at the top of this file). The
# `perf` label keeps it out of every CI preset's filter automatically;
# perf-nightly.yml is the only thing that asks for it.
set(GBM_PERF_COMMITS 100000 CACHE STRING
    "Commits in the commit-graph perf fixture. Calibrated -- see docs/PERFORMANCE.md before changing.")
set(GBM_PERF_SAMPLES 5 CACHE STRING
    "Off/on walk pairs per perf run. Forced odd by graph_check so the median is a real sample.")
set(GBM_PERF_MIN_SPEEDUP 2.0 CACHE STRING
    "Minimum commit-graph speedup asserted by the gate, roughly half the calibrated median.")
set(GBM_MAX_BYTES_PER_COMMIT 92.0 CACHE STRING
    "Maximum GraphSnapshot bytes/commit asserted by the nightly gate, ~18% above the measured
     post-oidOrder_ cost -- see docs/PERFORMANCE.md before changing. Kept in sync with
     GraphBuilderTest.cpp's MemoryStaysWithinTheBudget PR gate.")

if(GIT_FOUND)
    add_test(NAME commit_graph_speedup_ratio
        COMMAND "${CMAKE_COMMAND}"
                -DGIT_EXECUTABLE=${GIT_EXECUTABLE}
                -DGEN_HISTORY=$<TARGET_FILE:gen_history>
                -DWALKER=$<TARGET_FILE:gbm_graph_check>
                # Not graph_matches_git_on_generated_history's fixture-repo: the
                # two tests must never be able to delete each other's repository
                # mid-run.
                -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/perf-repo
                -DCOMMITS=${GBM_PERF_COMMITS}
                -DSAMPLES=${GBM_PERF_SAMPLES}
                -DMIN_SPEEDUP=${GBM_PERF_MIN_SPEEDUP}
                -DMAX_BYTES_PER_COMMIT=${GBM_MAX_BYTES_PER_COMMIT}
                -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunCommitGraphRatioCheck.cmake")
    set_tests_properties(commit_graph_speedup_ratio PROPERTIES
        LABELS "perf"
        # ~30s at 100k commits on a dev machine; slack here is deliberate for a
        # cold, shared runner -- a timeout on this test is a false alarm, not a
        # finding.
        TIMEOUT 600
        # A ctest -j neighbour saturating the machine is the largest noise
        # source available to a timing test. One property removes it.
        RUN_SERIAL TRUE
        ENVIRONMENT "GIT_OPTIONAL_LOCKS=0")
endif()

# --- capi (FFI) tests -------------------------------------------------------
# Gated on GBM_BUILD_CAPI so it builds under the capi-only preset.
if(GBM_BUILD_CAPI)
    add_executable(gbm_capi_tests
        capi/AskpassPollerTest.cpp
        capi/BisectApiTest.cpp
        capi/BlameApiTest.cpp
        capi/BranchApiTest.cpp
        capi/CallbackRegistryTest.cpp
        capi/CherryPickRevertApiTest.cpp
        capi/CommitFilesApiTest.cpp
        capi/CommitMetaApiTest.cpp
        capi/CompareApiTest.cpp
        capi/ConflictMarkerApiTest.cpp
        capi/DiscoveryApiTest.cpp
        capi/FileAtRevisionApiTest.cpp
        capi/FileHistoryApiTest.cpp
        capi/HistoryFilterApiTest.cpp
        capi/HistoryRefreshApiTest.cpp
        capi/IdentityApiTest.cpp
        capi/InitCloneApiTest.cpp
        capi/JsonCodecTest.cpp
        capi/LfsApiTest.cpp
        capi/MergeApiTest.cpp
        capi/OperationLogApiTest.cpp
        capi/OriginalOperationMessageApiTest.cpp
        capi/PatchApiTest.cpp
        capi/RebaseApiTest.cpp
        capi/ReflogApiTest.cpp
        capi/RemoteApiTest.cpp
        capi/ResetApiTest.cpp
        capi/SessionApiTest.cpp
        capi/StashApiTest.cpp
        capi/SubmoduleApiTest.cpp
        capi/TagApiTest.cpp
        capi/UndoApiTest.cpp
        capi/WorkingCopyApiTest.cpp
        capi/WorktreeApiTest.cpp
    )
    target_link_libraries(gbm_capi_tests
        PRIVATE gbm_capi gbm_core gbm_test_support GTest::gtest GTest::gtest_main gbm_warnings gbm_sanitizers)

    # gbm_capi is SHARED, so on Windows (no RPATH like Linux/macOS) the
    # loader can't find gbm_capi.dll unless it sits next to the .exe --
    # without this, even test *discovery* fails (the runner has to launch
    # the executable just to enumerate tests).
    if(WIN32)
        add_custom_command(TARGET gbm_capi_tests POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE:gbm_capi>" "$<TARGET_FILE_DIR:gbm_capi_tests>"
            COMMENT "Copying gbm_capi.dll next to gbm_capi_tests.exe")
    endif()

    gtest_discover_tests(gbm_capi_tests
        PROPERTIES LABELS "unit"
        DISCOVERY_TIMEOUT 60)
endif()

