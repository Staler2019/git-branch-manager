// ctest runs each test in its own process, in parallel with `-j`. A fixture repo
// named only after the test is then shared by every binary that has that test,
// and a sanitizer run beside a plain one makes one remove the other's `index.lock`.
#include "support/ProcessTempDir.h"

#include <filesystem>
#include <gtest/gtest.h>

namespace gbm::testing {
namespace {

TEST(ProcessTempDir, TheSystemTempDirectoryIsPrivateToThisProcess) {
    const std::string temp = std::filesystem::temp_directory_path().string();
    EXPECT_NE(temp.find(processTempDirName()), std::string::npos) << temp;
}

TEST(ProcessTempDir, TheDirectoryIsRemovedWithItsOwner) {
    std::filesystem::path made;
    {
        const ProcessTempDir owner;
        made = std::filesystem::temp_directory_path();
        ASSERT_TRUE(std::filesystem::is_directory(made));
        ASSERT_NE(made.string().find(processTempDirName()), std::string::npos);
    }
    EXPECT_FALSE(std::filesystem::exists(made));
}

}  // namespace
}  // namespace gbm::testing
