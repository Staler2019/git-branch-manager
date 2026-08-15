#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace gbm {

enum class RefKind : std::uint8_t { LocalBranch, RemoteBranch, Tag, Note, Stash, Other };

struct RefInfo {
    std::string fullName;   ///< e.g. refs/heads/main
    std::string shortName;  ///< e.g. main, origin/main, v1.2.0
    RefKind kind = RefKind::Other;
    ObjectId target;       ///< Peeled for annotated tags.
    ObjectId tagObject;    ///< The tag object itself, when annotated.
    std::string upstream;  ///< Full name of the upstream ref, if configured.
    int ahead = 0;
    int behind = 0;
    bool hasTrackingInfo = false;
    /// True when `%(upstream:track)` reported `[gone]`: `upstream` is a name
    /// git still remembers from `branch.<name>.remote`/`.merge` config, but
    /// the remote-tracking ref it names no longer exists (the remote was
    /// removed, or the branch was deleted upstream and pruned locally).
    bool isGone = false;
    bool isHead = false;
    bool isSymbolic = false;
    std::string worktreePath;  ///< Set when checked out in a linked worktree.
};

/// Where HEAD currently points.
struct HeadInfo {
    enum class Kind { Branch, Detached, Unborn } kind = Kind::Unborn;
    std::string branchName;  ///< Short name when kind == Branch.
    std::string fullRef;
    ObjectId target;
};

struct RefSnapshot {
    std::vector<RefInfo> refs;
    HeadInfo head;

    /// oid -> refs pointing at it, for decorating graph rows.
    std::unordered_map<ObjectId, std::vector<const RefInfo*>> byTarget;

    /// True when the ref count exceeded the guard and the history walk was
    /// narrowed. The UI surfaces this as "showing N of M refs" with a way to
    /// show everything, rather than silently hiding branches.
    bool refCountGuardTripped = false;
    std::size_t totalRefCount = 0;

    void buildIndex();

    const std::vector<const RefInfo*>* refsAt(const ObjectId& oid) const;

    std::vector<const RefInfo*> ofKind(RefKind kind) const;
};

using RefSnapshotPtr = std::shared_ptr<const RefSnapshot>;

/// Reads refs via a single `git for-each-ref`.
///
/// Ahead/behind counts come from `%(upstream:track)` in the same invocation.
/// Computing them per branch with `rev-list --count` would mean one process per
/// branch, which is minutes on a repository with thousands of refs.
class RefStore {
public:
    RefStore(IProcessRunner& runner, RepoPaths paths);

    /// Refs beyond this count trip the guard: a 10-year repository can carry
    /// thousands of stale branches, and drawing them all makes the graph useless
    /// as well as slow.
    static constexpr std::size_t kRefCountGuard = 2000;

    GitResult<RefSnapshotPtr> load(CancellationToken token);

    GitResult<HeadInfo> readHead(CancellationToken token);

    /// Ref tips to seed the history walk with, in the order they must be passed
    /// to rev-list. Seeding order is what assigns lane 0 to the trunk, so this
    /// deliberately lists HEAD and the trunk branch before anything else.
    /// Every tip has already passed refExists() -- a stale name (a deleted
    /// branch, or an upstream whose remote-tracking ref was pruned) is never
    /// returned here.
    static std::vector<std::string> historySeedRefs(const RefSnapshot& refs);

    /// Whether `fullName` (e.g. "refs/heads/main" or
    /// "refs/remotes/origin/main") names a ref actually present in `refs`
    /// right now. Every revision handed to `rev-list` as an explicit argument
    /// -- a seed tip, a branch-filter selection -- must pass this first: git
    /// rejects an unknown one with "fatal: ambiguous argument", which aborts
    /// the *entire* walk rather than just omitting that one tip.
    static bool refExists(const RefSnapshot& refs, const std::string& fullName);

    /// Whether a ref name is one git will accept, checked before we try to
    /// create it so the user gets a clear message instead of raw git output.
    static bool isValidBranchName(std::string_view name);

    /// Resolves a revision range (e.g. "A..B", or a single commit for the
    /// one-commit case) into the ordered list of commits it contains, oldest
    /// first -- the order a cherry-pick must apply them in, and the order a
    /// preview should list them in.
    GitResult<std::vector<ObjectId>> resolveRange(const std::string& range,
                                                  CancellationToken token);

    /// Resolves any single revision expression (branch, tag, short/long oid,
    /// HEAD~N, ...) to the commit it points to. `^{commit}` peels annotated
    /// tags to the commit they target, matching what every consumer of a
    /// resolved revision (e.g. a working-tree diff) actually wants. Fails
    /// with InvalidArgument if `revision` does not resolve.
    GitResult<ObjectId> resolveRevision(const std::string& revision, CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
