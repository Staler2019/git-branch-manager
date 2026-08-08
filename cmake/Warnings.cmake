add_library(gbm_warnings INTERFACE)

if(MSVC)
    target_compile_options(gbm_warnings INTERFACE /W4 /permissive- /utf-8 /Zc:__cplusplus /WX)
    target_compile_definitions(gbm_warnings INTERFACE
        _CRT_SECURE_NO_WARNINGS
        NOMINMAX                # else windows.h min/max macros break std::min
        WIN32_LEAN_AND_MEAN
        UNICODE _UNICODE)       # we only ever call the wide Win32 API
else()
    target_compile_options(gbm_warnings INTERFACE
        -Wall -Wextra -Wpedantic
        -Wcast-qual -Wshadow -Wnon-virtual-dtor -Woverloaded-virtual
        -Wdouble-promotion -Wformat=2
        -Werror)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        # GCC has a known false positive for -Wstringop-overread against
        # std::string_view::find() after inlining (e.g. CommitMeta.cpp's
        # parseRawCommit). Keep it visible as a warning without failing the
        # build on it.
        target_compile_options(gbm_warnings INTERFACE -Wno-error=stringop-overread)
    endif()
endif()
