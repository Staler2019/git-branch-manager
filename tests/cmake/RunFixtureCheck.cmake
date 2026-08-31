# Generates a synthetic repository, imports it with real git, then verifies our
# graph against git's own date order.
#
# Run via `cmake -P` from a ctest test, so it works identically on all three
# platforms without a shell script.

if(NOT GIT_EXECUTABLE OR NOT GEN_HISTORY OR NOT WALKER OR NOT WORK_DIR)
    message(FATAL_ERROR "RunFixtureCheck.cmake requires GIT_EXECUTABLE, GEN_HISTORY, WALKER and WORK_DIR")
endif()

# Modest by default so the test stays a sensible pull-request gate. The same
# generator produces a 200k-commit repository for the nightly performance run.
if(NOT DEFINED COMMITS)
    set(COMMITS 4000)
endif()

file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")

message(STATUS "Creating fixture repository in ${WORK_DIR}")

execute_process(
    COMMAND "${GIT_EXECUTABLE}" init --quiet --bare "${WORK_DIR}/.git"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "git init failed: ${result}")
endif()

# A bare init plus core.bare=false gives us a git dir with no checkout, which is
# all fast-import needs -- and skips writing thousands of files to disk.
execute_process(
    COMMAND "${GIT_EXECUTABLE}" -C "${WORK_DIR}" config core.bare false
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "git config failed: ${result}")
endif()

set(STREAM_FILE "${WORK_DIR}/history.fi")
execute_process(
    COMMAND "${GEN_HISTORY}" --commits ${COMMITS} --branches 12 --merge-rate 0.10
            --octopus 3 --tags 25 --seed 42
    OUTPUT_FILE "${STREAM_FILE}"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "gen_history failed: ${result}")
endif()

execute_process(
    COMMAND "${GIT_EXECUTABLE}" -C "${WORK_DIR}" fast-import --quiet
    INPUT_FILE "${STREAM_FILE}"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "git fast-import failed: ${result}")
endif()

# The commit-graph is what makes an ordered walk stream rather than stall, so
# the fixture carries one just like an optimised real repository would.
execute_process(
    COMMAND "${GIT_EXECUTABLE}" -C "${WORK_DIR}" commit-graph write --reachable --changed-paths
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(WARNING "commit-graph write failed (continuing): ${result}")
endif()

execute_process(
    COMMAND "${WALKER}" "${WORK_DIR}"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "graph verification failed: ${result}")
endif()

file(REMOVE_RECURSE "${WORK_DIR}")
message(STATUS "Fixture check passed")
