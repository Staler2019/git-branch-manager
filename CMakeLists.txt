cmake_minimum_required(VERSION 3.25)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")
include(Version)
gbm_derive_version(GBM_VERSION)

project(git-branch-manager
    VERSION ${GBM_VERSION}
    DESCRIPTION "A fast Git client for very large repositories"
    LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_C_STANDARD 11)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "" FORCE)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(GBM_BUILD_APP "Build the Qt GUI application" ON)
option(GBM_BUILD_CAPI "Build the FFI C API shared library for the Flutter UI" ON)
option(GBM_BUILD_TESTS "Build the test suite" ON)
option(GBM_SANITIZE "Enable sanitizers (address,undefined | thread)" "")
option(GBM_WERROR "Treat compiler warnings as errors (-Werror/-WX)" ON)

include(Sanitizers)
include(Warnings)
include(Format)

# ---------------------------------------------------------------------------
# Dependencies. Deliberately tiny: no vcpkg, no Conan. FetchContent with
# pinned tags keeps CI fast and avoids the vcpkg binary-cache problem.
# ---------------------------------------------------------------------------
include(Dependencies)

add_subdirectory(src/core)

if(GBM_BUILD_APP)
    add_subdirectory(src/app)
endif()

if(GBM_BUILD_CAPI)
    add_subdirectory(src/capi)
endif()

if(GBM_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

include(Packaging)
