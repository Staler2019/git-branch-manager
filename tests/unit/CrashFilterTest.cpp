#include "core/base/CrashFilter.h"

#include <gtest/gtest.h>

namespace gbm {
namespace {

constexpr std::uint32_t kAccessViolation = 0xC0000005u;
constexpr std::uint32_t kStackOverflow = 0xC00000FDu;

TEST(ShouldShowCrashDialog, OnlyWhenNothingOfThisProcessIsOnScreenYet) {
    EXPECT_TRUE(shouldShowCrashDialog(kAccessViolation, false, false, false));
    EXPECT_FALSE(shouldShowCrashDialog(kAccessViolation, false, false, true));
}

// git waits on the askpass process, and it never has a window, so a box there would
// appear in the middle of a background fetch and hold git until someone clicked it.
TEST(ShouldShowCrashDialog, NeverInTheAskpassProcess) {
    EXPECT_FALSE(shouldShowCrashDialog(kAccessViolation, true, false, false));
}

// The filter runs on the overflowed stack; showing anything is a second fault.
TEST(ShouldShowCrashDialog, NeverForAStackOverflow) {
    EXPECT_FALSE(shouldShowCrashDialog(kStackOverflow, false, false, false));
}

TEST(ShouldShowCrashDialog, NeverWhenSwitchedOffForTests) {
    EXPECT_FALSE(shouldShowCrashDialog(kAccessViolation, false, true, false));
}

}  // namespace
}  // namespace gbm
