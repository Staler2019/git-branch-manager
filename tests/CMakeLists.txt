include(GoogleTest)

# Source-only, so deliberately not inside the GBM_BUILD_APP guard below: this
# must gate the core-only, asan-ubsan and tsan presets too, not just the full
# app builds -- it reads src/app's *text*, not anything that needs Qt to
# compile. See CheckNoDuplicateRefRefresh.cmake for why this is a source check
# rather than a runtime one.
add_test(NAME no_duplicate_ref_refresh_call_sites
    COMMAND "${CMAKE_COMMAND}"
            -DSOURCE_DIR=${CMAKE_SOURCE_DIR}
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/CheckNoDuplicateRefRefresh.cmake")
set_tests_properties(no_duplicate_ref_refresh_call_sites PROPERTIES LABELS "unit")

# Test doubles live here rather than in the shipped library.
add_library(gbm_test_support STATIC support/FakeProcessRunner.cpp)
target_include_directories(gbm_test_support PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(gbm_test_support PUBLIC gbm_core PRIVATE gbm_warnings)

# --- core unit + integration tests (no Qt needed) --------------------------
add_executable(gbm_core_tests
    unit/CoreBasicsTest.cpp
    unit/DiscoveryTest.cpp
    unit/GitIntegrationTest.cpp
    unit/GraphBuilderTest.cpp
    unit/MaintenanceOpsTest.cpp
    unit/ProcessRunnerTest.cpp
    unit/SideBySideDiffTest.cpp
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

# --- Qt model tests --------------------------------------------------------
# Only when the GUI is being built. Runs offscreen, so it needs no display in CI.
if(GBM_BUILD_APP)
    find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Widgets Svg Test)

    # Shared by gbm_model_tests and gbm_model_perf_tests below: both link the
    # models/bridge code their respective QtTest binary exercises, and a perf
    # split that silently drifted from what "unit" actually covers would be
    # worse than the duplication it replaces.
    set(GBM_MODEL_TEST_SOURCES
        "${CMAKE_SOURCE_DIR}/src/app/models/CommitListModel.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/bridge/AskpassWatcher.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/bridge/RepositorySession.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/bridge/ThemeManager.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/theme/ThemeTokens.cpp"
        "${CMAKE_SOURCE_DIR}/resources/app.qrc")

    qt_add_executable(gbm_model_tests ui/ModelsTest.cpp
        ${GBM_MODEL_TEST_SOURCES}
        "${CMAKE_SOURCE_DIR}/src/app/models/GraphColumnDelegate.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/models/RefTreeModel.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/models/RepoListModel.cpp")

    # qt_standard_project_setup() is directory-scoped and lives in src/app, so this
    # target needs AUTOMOC turned on explicitly -- the models are all QObjects.
    # AUTORCC is needed now that GraphColumnDelegate pulls in ThemeManager,
    # which reads the theme QSS/fonts from resources/app.qrc.
    set_target_properties(gbm_model_tests PROPERTIES AUTOMOC ON AUTORCC ON)

    target_include_directories(gbm_model_tests PRIVATE "${CMAKE_SOURCE_DIR}/src")
    target_link_libraries(gbm_model_tests
        PRIVATE gbm_core Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Test gbm_warnings)

    add_test(NAME qt_models COMMAND gbm_model_tests)
    set_tests_properties(qt_models PROPERTIES
        LABELS "unit"
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    # Wall-clock assertions are too noisy on shared CI runners to gate every
    # PR (see commit_graph_speedup_ratio above), so CommitListModel's
    # non-blocking-data() timing check gets its own "perf" binary rather than
    # living in gbm_model_tests' "unit" one. Separate qt_add_executable for
    # the same QTEST_MAIN-per-binary reason as gbm_theme_tests below.
    qt_add_executable(gbm_model_perf_tests ui/ModelsPerfTest.cpp ${GBM_MODEL_TEST_SOURCES})

    set_target_properties(gbm_model_perf_tests PROPERTIES AUTOMOC ON AUTORCC ON)

    target_include_directories(gbm_model_perf_tests PRIVATE "${CMAKE_SOURCE_DIR}/src")
    target_link_libraries(gbm_model_perf_tests
        PRIVATE gbm_core Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Test gbm_warnings)

    add_test(NAME qt_models_perf COMMAND gbm_model_perf_tests)
    set_tests_properties(qt_models_perf PROPERTIES
        LABELS "perf"
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    # Separate binary rather than an extra source in gbm_model_tests: QtTest's
    # QTEST_MAIN macro defines main() once per binary, and ModelsTest.cpp
    # already claims it. The theme foundation (ThemeManager + the token
    # table) needs the app.qrc resource for the "no unresolved @ placeholder"
    # check, so it gets its own qt_add_executable mirroring gbm_model_tests.
    qt_add_executable(gbm_theme_tests ui/ThemeTest.cpp
        "${CMAKE_SOURCE_DIR}/src/app/bridge/ThemeManager.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/theme/IconLoader.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/theme/ThemeTokens.cpp"
        "${CMAKE_SOURCE_DIR}/resources/app.qrc")

    set_target_properties(gbm_theme_tests PROPERTIES AUTOMOC ON AUTORCC ON)

    target_include_directories(gbm_theme_tests PRIVATE "${CMAKE_SOURCE_DIR}/src")
    target_link_libraries(gbm_theme_tests
        PRIVATE gbm_core Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Svg Qt6::Test gbm_warnings)

    add_test(NAME qt_theme COMMAND gbm_theme_tests)
    set_tests_properties(qt_theme PROPERTIES
        LABELS "unit"
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
