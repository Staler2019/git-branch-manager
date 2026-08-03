# `format` reformats src/ in place; `format-check` reproduces the CI
# `lint` job's clang-format gate (.github/workflows/ci.yml) without mutating
# anything. Both just shell out to scripts/, which is what a developer without
# CMake configured yet would run directly -- this only exists so the same
# commands are reachable as `cmake --build build/dev --target format`.
add_custom_target(format
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/scripts/format.sh"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Applying clang-format 18 to src/"
    VERBATIM)

add_custom_target(format-check
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/scripts/format-check.sh"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Checking src/ is clang-format-clean"
    VERBATIM)
