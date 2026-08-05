# Fails if any call site in src/app calls refreshRefs() and refreshHistory()
# back to back instead of refreshRefsAndHistory().
#
# A source check rather than a behavioural one, and that is the point.
# RepositorySession is a QObject that builds its own IProcessRunner in its
# constructor and delivers everything through a ThreadPool and queued signals,
# so asserting "exactly one for-each-ref per refresh" at runtime would need a
# runner-injection seam, a QCoreApplication and an event loop -- an async
# harness this repository does not have, for a bug whose entire shape is
# visible in the source. docs/PERFORMANCE.md's "UI refresh path" section has
# the measurement that makes it worth a gate: one for-each-ref on a
# 3,798-ref repository cost more than the whole 50k-commit rev-list walk
# after it, and the old code paid for it twice on every refresh.
#
# .github/workflows/ci.yml's "core must not depend on Qt" grep-based check is
# the precedent for gating on source shape rather than runtime behaviour.

if(NOT SOURCE_DIR)
    message(FATAL_ERROR "CheckNoDuplicateRefRefresh.cmake requires SOURCE_DIR")
endif()

file(GLOB_RECURSE sources "${SOURCE_DIR}/src/app/*.cpp")

set(offenders "")
foreach(file IN LISTS sources)
    file(READ "${file}" text)

    # Comments are stripped first: RepositorySession.cpp's own doc comments
    # discuss both function names in prose (explaining exactly this rule) and
    # would otherwise trip this check. The block-comment pattern is the
    # standard greedy-safe form, needed because CMake's regex engine has no
    # non-greedy quantifier.
    string(REGEX REPLACE "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/" "" text "${text}")
    string(REGEX REPLACE "//[^\n]*" "" text "${text}")

    # "refreshRefs();" followed, before the next statement ends, by
    # "refreshHistory(" -- and the same pair in the other order. [^;]* cannot
    # cross a semicolon, so this only matches genuinely adjacent statements,
    # not two unrelated calls somewhere in the same function.
    if(text MATCHES "refreshRefs\\(\\)[ \t\r\n]*;[^;]*refreshHistory\\(" OR
       text MATCHES "refreshHistory\\([^;]*;[^;]*refreshRefs\\(\\)")
        list(APPEND offenders "${file}")
    endif()
endforeach()

if(offenders)
    string(REPLACE ";" "\n  " pretty "${offenders}")
    message(FATAL_ERROR
        "refreshRefs() and refreshHistory() are called back to back in:\n  ${pretty}\n"
        "Each independently re-runs `git for-each-ref`. Call "
        "RepositorySession::refreshRefsAndHistory() instead, which shares one "
        "load between them -- see docs/PERFORMANCE.md, \"UI refresh path\".")
endif()

message(STATUS "No duplicate refreshRefs()/refreshHistory() pairs in src/app")
