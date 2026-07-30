# GBM_SANITIZE is a comma-separated list understood by -fsanitize=, e.g.
#   -DGBM_SANITIZE=address,undefined
#   -DGBM_SANITIZE=thread
# Thread sanitizer matters most here: the snapshot-publishing path between the
# worker pool and the UI thread is exactly where a data race would hide.
add_library(gbm_sanitizers INTERFACE)

if(GBM_SANITIZE AND NOT MSVC)
    message(STATUS "Sanitizers enabled: ${GBM_SANITIZE}")
    target_compile_options(gbm_sanitizers INTERFACE
        -fsanitize=${GBM_SANITIZE} -fno-omit-frame-pointer -g)
    target_link_options(gbm_sanitizers INTERFACE -fsanitize=${GBM_SANITIZE})
elseif(GBM_SANITIZE AND MSVC)
    message(STATUS "Sanitizers enabled: address (MSVC supports ASan only)")
    target_compile_options(gbm_sanitizers INTERFACE /fsanitize=address)
endif()
