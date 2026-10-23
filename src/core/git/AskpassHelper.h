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

/// The environment variable wire() uses to tell the askpass child where its
/// request directory is; ProcessRunner reads it back out of envOverrides to
/// know which directory to watch for a pending prompt.
inline constexpr std::string_view kDirEnvVar = "GBM_ASKPASS_DIR";

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

/// For a command nobody pressed a button for (the background auto fetch):
/// every prompt git or ssh could raise must fail at once rather than appear.
/// GIT_TERMINAL_PROMPT=0 alone does not get there -- git asks GIT_ASKPASS,
/// then `core.askPass`, then SSH_ASKPASS before it ever looks at it, and an
/// app started from an IDE terminal inherits that IDE's GIT_ASKPASS. So both
/// askpass variables point at this executable with an *empty* request
/// directory, which runClient() answers with exit 1; Git Credential Manager is
/// told not to open its own window. The ssh command is deliberately left
/// alone: overriding GIT_SSH_COMMAND would replace the user's
/// `core.sshCommand` (a chosen key, a ProxyCommand), and SSH_ASKPASS_REQUIRE
/// already makes ssh's passphrase and host-key questions go to the client.
void wireRefusing(GitCommand& command);

/// Creates a fresh, empty, owner-only per-request directory under the system
/// temp directory -- `mkdtemp` on POSIX (0700, unpredictable name, never an
/// existing directory), since on Linux that is the shared /tmp. Returns an
/// empty path on failure (out of disk space, no temp directory), in which case
/// the caller should proceed without askpass wiring rather than fail the whole
/// operation over a UI nicety.
std::filesystem::path makeRequestDir();

/// Writes one handshake file (`kRequestFile`, `kResponseFile` or
/// `kCancelFile`) into `dir`: owner read/write only (0600 on POSIX; on
/// Windows the per-user %TEMP% ACL), and atomically, through a temp file and
/// a same-directory rename, so the polling side never reads it half written.
/// Replaces an earlier file of the same name. Returns false on any failure.
bool writeHandshakeFile(const std::filesystem::path& dir,
                        std::string_view fileName,
                        std::string_view content);

/// Whether a credential prompt in `dir` is waiting for the user: the client
/// has written `kRequestFile` and neither an answer nor a cancel has arrived.
/// git writes nothing while it waits, so ProcessRunner suspends a command's
/// idle deadline for as long as this holds. False for an empty `dir`.
bool isPromptPending(const std::filesystem::path& dir);

/// The askpass client's core, taking the request directory and prompt
/// directly rather than reading them from argv/the environment -- this is what
/// makes the protocol unit-testable without setenv or a subprocess. `dir`
/// must already exist; it is never created here. Blocks until `dir`/response
/// or `dir`/cancel appears, `dir` itself disappears, or kResponseTimeout
/// elapses.
/// Returns 0 with the secret written to stdout, or 1 otherwise.
int runClientForDir(const std::filesystem::path& dir, const std::string& prompt);

/// The askpass client. Reached from each desktop runner's `main` through
/// gbm_askpass_main() (capi) as soon as GBM_ASKPASS_MODE=1 is found in the
/// environment -- before the engine or anything else starts, since git is
/// blocked waiting on this process's stdout. `argv[1]` is the prompt text git
/// supplies (e.g. "Username for 'https://github.com': "). Reads GBM_ASKPASS_DIR
/// from the environment and delegates to runClientForDir().
int runClient(int argc, const char* const* argv);

}  // namespace gbm::askpass
