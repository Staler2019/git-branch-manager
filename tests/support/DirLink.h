#pragma once

#include <filesystem>
#include <system_error>

namespace gbm::testing {

/// Makes [link] a directory link to [target], without a shell.
///
/// POSIX: a symlink. Windows: an NTFS junction, which -- unlike a directory
/// symlink -- needs neither administrator rights nor Developer Mode, so it
/// works on any CI runner. [target] is made absolute, because a junction
/// cannot be relative. Fails (false, [ec] set) when [link] already exists.
bool makeDirectoryLink(const std::filesystem::path& target,
                       const std::filesystem::path& link,
                       std::error_code& ec);

}  // namespace gbm::testing
