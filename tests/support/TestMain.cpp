// Replaces GTest::gtest_main for the test binaries that create fixture repositories.
#include "support/ProcessTempDir.h"

#include <gtest/gtest.h>

int main(int argc, char** argv) {
    const gbm::testing::ProcessTempDir tempDir;
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
