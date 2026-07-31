include(GoogleTest)

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

# --- Qt model tests --------------------------------------------------------
# Only when the GUI is being built. Runs offscreen, so it needs no display in CI.
if(GBM_BUILD_APP)
    find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Widgets Test)

    qt_add_executable(gbm_model_tests ui/ModelsTest.cpp
        "${CMAKE_SOURCE_DIR}/src/app/models/CommitListModel.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/models/GraphColumnDelegate.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/models/RefTreeModel.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/models/RepoListModel.cpp"
        "${CMAKE_SOURCE_DIR}/src/app/bridge/RepositorySession.cpp")

    # qt_standard_project_setup() is directory-scoped and lives in src/app, so this
    # target needs AUTOMOC turned on explicitly -- the models are all QObjects.
    set_target_properties(gbm_model_tests PROPERTIES AUTOMOC ON)

    target_include_directories(gbm_model_tests PRIVATE "${CMAKE_SOURCE_DIR}/src")
    target_link_libraries(gbm_model_tests
        PRIVATE gbm_core Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Test gbm_warnings)

    add_test(NAME qt_models COMMAND gbm_model_tests)
    set_tests_properties(qt_models PROPERTIES
        LABELS "unit"
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
