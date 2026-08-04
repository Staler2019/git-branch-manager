#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"

#include <memory>
#include <string>

namespace gbm {

/// The repository-local (`git config --local`) Git identity, as of the last
/// read. Distinct from any global `user.name`/`user.email` in `~/.gitconfig`
/// -- this app currently has no reader for that global value (see
/// PreferencesDialog's honest limits), only for the per-repository override
/// this store reads.
struct LocalIdentity {
    std::string name;   ///< Empty if `user.name` is unset locally.
    std::string email;  ///< Empty if `user.email` is unset locally.
    /// True when either key is set locally -- i.e. an override is active.
    bool overridden = false;
};

/// `user.name`/`user.email` as git itself would resolve them for a new
/// commit here: `--local` if set, otherwise falling back to `--global`/
/// system config. Unlike LocalIdentity this has no "overridden" notion --
/// it is simply whichever value wins.
struct EffectiveIdentity {
    std::string name;
    std::string email;
};

/// Reads `user.name`/`user.email` scoped `--local` to one repository.
/// Read-only, like RefStore/RemoteStore.
class LocalIdentityStore {
public:
    LocalIdentityStore(IProcessRunner& runner, RepoPaths paths);

    /// Never fails on an unset key -- `git config --get` exiting 1 with no
    /// stderr just means "nothing here", not an error worth surfacing.
    GitResult<LocalIdentity> read(CancellationToken token);

    /// Same tolerance for an unset key, but without `--local`, so the result
    /// matches whatever identity `git commit` would actually attribute a new
    /// commit to (used to decide whether a commit in the graph is "mine").
    GitResult<EffectiveIdentity> readEffective(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct SetLocalIdentityRequest {
    std::string name;
    std::string email;
};

/// `git config --local user.name <name>` then `user.email <email>`. Used only
/// when the "Override the global Git identity for this repository only"
/// checkbox is on.
std::unique_ptr<Operation> makeSetLocalIdentityOperation(SetLocalIdentityRequest request);

/// `git config --local --unset user.name` / `--unset user.email`, best-effort:
/// unsetting a key that was never set exits non-zero but is not treated as a
/// failure here, since the goal is simply "no override remains".
std::unique_ptr<Operation> makeClearLocalIdentityOperation();

}  // namespace gbm
