# Builds a large synthetic repository, then measures the history walk with and
# without git's commit-graph on that same repository and fails if the graph has
# stopped paying for itself.
#
# Separate from RunFixtureCheck.cmake, which is the correctness gate: this
# needs a much larger fixture, needs the commit-graph write to be fatal rather
# than a warning (without one there is nothing to compare), and turns off
# every background git job that could rewrite the repository mid-measurement.
#
# Run via `cmake -P` from a ctest test, so it works identically on all three
# platforms without a shell script.

if(NOT GIT_EXECUTABLE OR NOT GEN_HISTORY OR NOT WALKER OR NOT WORK_DIR)
    message(FATAL_ERROR "RunCommitGraphRatioCheck.cmake requires GIT_EXECUTABLE, GEN_HISTORY, WALKER and WORK_DIR")
endif()

# Calibrated, not guessed -- see docs/PERFORMANCE.md's "commit-graph speedup
# gate" section for the measurements this came from. At this size the
# in-process A/B toggle's graph-on arm lands around 100-110ms, comfortably
# above gbm_graph_check's 50ms floor (below which clock resolution and
# process-spawn cost dominate and the ratio stops meaning anything) even on a
# CI runner meaningfully faster than the machine this was calibrated on.
if(NOT DEFINED COMMITS)
    set(COMMITS 100000)
endif()
if(NOT DEFINED SAMPLES)
    set(SAMPLES 5)
endif()
if(NOT DEFINED MIN_SPEEDUP)
    set(MIN_SPEEDUP 2.0)
endif()
if(NOT DEFINED MAX_BYTES_PER_COMMIT)
    set(MAX_BYTES_PER_COMMIT 92.0)
endif()

file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")

message(STATUS "Creating a ${COMMITS}-commit perf fixture in ${WORK_DIR}")

execute_process(
    COMMAND "${GIT_EXECUTABLE}" init --quiet --bare "${WORK_DIR}/.git"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "git init failed: ${result}")
endif()

# core.bare=false gives a git dir with no checkout, which is all fast-import
# needs. The rest turn off everything git might otherwise decide to do on its
# own: an auto-gc, a repack, or an opportunistic commit-graph write landing
# between the two arms would silently change what is being compared. These are
# throwaway fixtures, so switching all of it off costs nothing.
set(FIXTURE_CONFIG_KEYS core.bare gc.auto gc.autoDetach gc.writeCommitGraph
    maintenance.auto fetch.writeCommitGraph core.fsmonitor core.untrackedCache)
set(FIXTURE_CONFIG_VALUES false 0 false false false false false false)
list(LENGTH FIXTURE_CONFIG_KEYS fixtureConfigCount)
math(EXPR fixtureConfigLast "${fixtureConfigCount} - 1")
foreach(fixtureConfigIndex RANGE ${fixtureConfigLast})
    list(GET FIXTURE_CONFIG_KEYS ${fixtureConfigIndex} fixtureConfigKey)
    list(GET FIXTURE_CONFIG_VALUES ${fixtureConfigIndex} fixtureConfigValue)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${WORK_DIR}" config "${fixtureConfigKey}" "${fixtureConfigValue}"
        RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "git config ${fixtureConfigKey} failed: ${result}")
    endif()
endforeach()

# Same topology knobs as RunFixtureCheck.cmake so the two fixtures stay
# comparable; only the commit count is scaled up for a measurable A/B ratio.
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
file(REMOVE "${STREAM_FILE}")

# FATAL here, unlike RunFixtureCheck.cmake's WARNING: without a commit-graph
# there is nothing for the "graph on" arm to use, and the whole comparison is
# meaningless.
execute_process(
    COMMAND "${GIT_EXECUTABLE}" -C "${WORK_DIR}" commit-graph write --reachable --changed-paths
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "commit-graph write failed: ${result}")
endif()

# ERROR_VARIABLE, not OUTPUT_VARIABLE: gbm_graph_check prints every timing to
# stderr and reserves stdout for the optional ASCII render. ECHO_ERROR_VARIABLE
# keeps it visible live too, so a run that hits the ctest timeout still shows
# how far it got.
execute_process(
    COMMAND "${WALKER}" "${WORK_DIR}"
            --commit-graph-ab ${SAMPLES}
            --min-graph-speedup ${MIN_SPEEDUP}
            --max-bytes-per-commit ${MAX_BYTES_PER_COMMIT}
    ERROR_VARIABLE measurements
    ECHO_ERROR_VARIABLE
    RESULT_VARIABLE result)

if(NOT result EQUAL 0)
    # Deliberately not cleaned up: a perf failure is worth re-measuring by
    # hand, and rebuilding ${COMMITS} commits just to reproduce it wastes time
    # that a kept fixture avoids.
    message(FATAL_ERROR "commit-graph ratio check failed (${result}) -- fixture kept at ${WORK_DIR}")
endif()

file(REMOVE_RECURSE "${WORK_DIR}")
message(STATUS "commit-graph ratio check passed")
