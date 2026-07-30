# Derives the project version, in priority order:
#   1. $GITHUB_REF_NAME when it looks like vX.Y.Z (tag-triggered release builds)
#   2. `git describe --tags` (local builds in a tagged clone)
#   3. 0.0.0 (fresh clone with no tags)
#
# The full descriptive string (with commit and -dirty) is exported separately as
# GBM_VERSION_STRING, because project(VERSION) only accepts numeric triples.
function(gbm_derive_version out_var)
    set(_numeric "0.0.0")
    set(_full "")

    if(DEFINED ENV{GITHUB_REF_NAME} AND "$ENV{GITHUB_REF_NAME}" MATCHES "^v([0-9]+\\.[0-9]+\\.[0-9]+)$")
        set(_numeric "${CMAKE_MATCH_1}")
        set(_full "$ENV{GITHUB_REF_NAME}")
    else()
        find_package(Git QUIET)
        if(GIT_FOUND)
            execute_process(
                COMMAND "${GIT_EXECUTABLE}" describe --tags --dirty --always
                WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
                OUTPUT_VARIABLE _described
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET)
            if(_described)
                set(_full "${_described}")
                if(_described MATCHES "^v?([0-9]+\\.[0-9]+\\.[0-9]+)")
                    set(_numeric "${CMAKE_MATCH_1}")
                endif()
            endif()
        endif()
    endif()

    if(NOT _full)
        set(_full "${_numeric}-dev")
    endif()

    set(${out_var} "${_numeric}" PARENT_SCOPE)
    set(GBM_VERSION_STRING "${_full}" CACHE INTERNAL "Descriptive version string")
    message(STATUS "git-branch-manager version: ${_full} (numeric ${_numeric})")
endfunction()
