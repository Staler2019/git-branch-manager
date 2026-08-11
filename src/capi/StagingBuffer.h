#pragma once

// The thread-local synchronous-result buffer documented in gbm_capi.h
// (gbm_last_result_json_len/gbm_last_result_json_copy). Any capi .cpp file
// that implements a "populates the staging buffer" function writes through
// setStagingBuffer(); Handle.cpp implements the two extern "C" accessors.

#include <string>

namespace gbm::capi {

void setStagingBuffer(std::string json);
const std::string& stagingBuffer();

}  // namespace gbm::capi
