#pragma once

#include "core/git/GitCommand.h"

#include <filesystem>
#include <string_view>

namespace gbm::askpass {

/// The three files that make up the handshake in a request directory. The
/// askpass child (this same executable, re-invoked by git) writes `kRequestFile`
/// and blocks; the running application writes `kResponseFile` once the user has
/// answered, or `kCancelFile` if they dismissed the prompt.
///
/// A file-based handshake rather than a socket because `core` has no networking
/// primitive of its own and does not need one here: a human is being asked to
/// type a password, so polling every 150 ms adds no perceptible latency.
inline constexpr std::string_view kRequestFile = "request";
inline constexpr std::string_view kResponseFile = "response";
inline constexpr std::string_view kCancelFile = "cancel";

/// How long the askpass child waits for an answer before giving up and failing
/// the git invocation. Generous, because the human might be looking something
/// up (a password manager, a hardware key), but not unbounded: an abandoned
/// prompt must not wedge the operation queue forever.
inline constexpr auto kResponseTimeout = std::chrono::minutes(10);

/// Points GIT_ASKPASS and SSH_ASKPASS at the current executable and tells it
/// (via GBM_ASKPASS_DIR) which request directory to use, so any credential
/// prompt raised while `command` runs is routed back to the application instead
/// of failing immediately or hanging on a nonexistent terminal. `dir` must
/// already exist and is not created here -- see makeRequestDir().
///
/// Safe to call with `dir` empty: no overrides are added, and the command
/// behaves exactly as it did before askpass support existed (git still fails
/// cleanly on an auth prompt, since GIT_TERMINAL_PROMPT is always 0).
void wire(GitCommand& command, const std::filesystem::path& dir);

/// Creates a fresh, empty per-request directory under the system temp
/// directory. Returns an empty path on failure (out of disk space, no temp
/// directory), in which case the caller should proceed without askpass wiring
/// rather than fail the whole operation over a UI nicety.
std::filesystem::path makeRequestDir();

/// The askpass client's core, taking the request directory and prompt
/// directly rather than reading them from argv/the environment -- this is what
/// makes the protocol unit-testable without setenv or a subprocess. Blocks
/// until `dir`/response or `dir`/cancel appears, or kResponseTimeout elapses.
/// Returns 0 with the secret written to stdout, or 1 otherwise.
int runClientForDir(const std::filesystem::path& dir, const std::string& prompt);

/// The askpass client. Called from main() as soon as GBM_ASKPASS_MODE=1 is
/// found in the environment -- before Qt or anything else starts, since git is
/// blocked waiting on this process's stdout. `argv[1]` is the prompt text git
/// supplies (e.g. "Username for 'https://github.com': "). Reads GBM_ASKPASS_DIR
/// from the environment and delegates to runClientForDir().
int runClient(int argc, char** argv);

}  // namespace gbm::askpass
