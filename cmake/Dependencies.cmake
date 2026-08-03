include(FetchContent)

set(FETCHCONTENT_QUIET OFF)

# --- SQLite ----------------------------------------------------------------
# Prefer the system library; fall back to the amalgamation. The amalgamation is
# a single C file, so the fallback costs a couple of seconds, not minutes.
find_package(SQLite3 QUIET)
if(SQLite3_FOUND)
    message(STATUS "Using system SQLite3 ${SQLite3_VERSION}")
    add_library(gbm_sqlite3 INTERFACE)
    target_link_libraries(gbm_sqlite3 INTERFACE SQLite3::SQLite3)
else()
    message(STATUS "System SQLite3 not found; fetching amalgamation")
    # SHA3-256 because that is what sqlite.org publishes next to the download,
    # so the pin can be re-checked against upstream by eye.
    FetchContent_Declare(sqlite_amalgamation
        URL https://www.sqlite.org/2024/sqlite-amalgamation-3450100.zip
        URL_HASH SHA3_256=e311198775d5d5b2889d5fabe1d9a490567a14e605591d6a9e4c833804a8b4cb
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    FetchContent_MakeAvailable(sqlite_amalgamation)
    add_library(gbm_sqlite3_impl STATIC "${sqlite_amalgamation_SOURCE_DIR}/sqlite3.c")
    target_include_directories(gbm_sqlite3_impl SYSTEM PUBLIC "${sqlite_amalgamation_SOURCE_DIR}")
    target_compile_definitions(gbm_sqlite3_impl PRIVATE
        SQLITE_ENABLE_FTS5 SQLITE_THREADSAFE=1 SQLITE_DQS=0 SQLITE_OMIT_DEPRECATED)
    add_library(gbm_sqlite3 INTERFACE)
    target_link_libraries(gbm_sqlite3 INTERFACE gbm_sqlite3_impl)
endif()

# --- GoogleTest ------------------------------------------------------------
if(GBM_BUILD_TESTS)
    FetchContent_Declare(googletest
        GIT_REPOSITORY https://github.com/google/googletest.git
        GIT_TAG v1.15.2
        GIT_SHALLOW TRUE)
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    set(BUILD_GMOCK ON CACHE BOOL "" FORCE)
    set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(googletest)
endif()
