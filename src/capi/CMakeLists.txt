# The FFI boundary consumed by app_flutter/ via dart:ffi. Links only
# gbm_core (no Qt) so it builds under the same Qt-free presets as the core
# library -- see the CI grep check in .github/workflows/ci.yml and
# docs/ARCHITECTURE.md's core/app split.
add_library(gbm_capi SHARED
    AskpassPoller.cpp
    Bisect.cpp
    Blame.cpp
    Branches.cpp
    CallbackRegistry.cpp
    CherryPick.cpp
    Conflicts.cpp
    Discovery.cpp
    FileHistory.cpp
    Graph.cpp
    Handle.cpp
    History.cpp
    JsonCodec.cpp
    Lfs.cpp
    Merge.cpp
    Patch.cpp
    Rebase.cpp
    Reflog.cpp
    Refs.cpp
    Remotes.cpp
    ResetRestore.cpp
    Revert.cpp
    Session.cpp
    Stash.cpp
    Submodules.cpp
    Tags.cpp
    Undo.cpp
    WorkingCopy.cpp
    Worktrees.cpp
)

target_include_directories(gbm_capi PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../")

target_link_libraries(gbm_capi
    PUBLIC gbm_core
    PRIVATE gbm_warnings gbm_sanitizers)

# Deliberately NOT hidden-by-default: tests/capi links this target directly
# to white-box-test the internal C++ classes (CallbackRegistry, JsonCodec)
# the same way gbm_core_tests links gbm_core, rather than only exercising
# them indirectly through the extern "C" surface. That leaves every C++
# symbol exported alongside the GBM_API ones, which is harmless here --
# Dart's dart:ffi resolves functions by name via dlopen/dlsym and never
# touches the C++ symbol table -- but revisit with a version script or
# -fvisibility=hidden + explicit exports if gbm_capi ever needs a minimal
# public surface (e.g. to ship a stripped release binary).
set_target_properties(gbm_capi PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
