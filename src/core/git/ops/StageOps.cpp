#include "core/git/ops/StageOps.h"

#include "core/git/DiffService.h"

#include <utility>

namespace gbm {

namespace {

/// Shared by ApplyPatchOperation, PartialStageOperation and
/// DiscardLinesOperation: `git apply [--cached] [--reverse]` fed `patch` on
/// stdin. `--whitespace=nowarn`: a partial stage must not fail just because
/// the hunk it was cut from trails whitespace elsewhere in the file.
///
/// `cached` is what separates staging from discarding: with it, only the
/// index moves and the work tree is untouched; without it, git rewrites the
/// file on disk. Every staging caller passes true -- only
/// DiscardLinesOperation passes false, and it is destructive precisely
/// because of that.
GitResult<ProcessResult> applyPatch(IProcessRunner& runner,
                                    const RepoPaths& paths,
                                    const std::string& patch,
                                    bool cached,
                                    bool reverse,
                                    CancellationToken token) {
    std::vector<std::string> args{"apply"};
    if (cached) {
        args.emplace_back("--cached");
    }
    args.emplace_back("--whitespace=nowarn");
    if (reverse) {
        args.emplace_back("--reverse");
    }
    args.emplace_back("-");

    GitCommand command(paths.commandDir(), std::move(args));
    command.stdinData = patch;
    command.timeout = std::chrono::seconds(60);
    return runner.run(command, token);
}

GitResult<ProcessResult> applyPatchToIndex(IProcessRunner& runner,
                                           const RepoPaths& paths,
                                           const std::string& patch,
                                           bool reverse,
                                           CancellationToken token) {
    return applyPatch(runner, paths, patch, /*cached=*/true, reverse, token);
}

class StageFilesOperation final : public Operation {
public:
    explicit StageFilesOperation(StageFilesRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.paths.size() == 1
                   ? "Stage " + request_.paths.front()
                   : "Stage " + std::to_string(request_.paths.size()) + " files";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.paths.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No files selected to stage");
            return outcome;
        }

        std::vector<std::string> args{"add", "--"};
        for (const std::string& path : request_.paths) {
            args.push_back(path);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(120);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    StageFilesRequest request_;
};

/// True when `selected` covers every *changed* line of a file the index
/// reports as Added -- i.e. unstaging this selection would leave the index
/// holding nothing at all for the path.
///
/// The three clauses are not equally load-bearing, and saying which is which
/// is the point of this comment.
///
/// "Every changed line" is the one a test can disagree with: a *partial*
/// unstage of an added file is already correct today -- it leaves a shorter
/// `A`, which is what the user asked for -- and answering that one with
/// `restore --staged` would throw away the part of the stage they kept.
/// Dropping this clause reddens UnstagingOneLineOfAnUntrackedFileKeepsTheRest-
/// Staged, and nothing else.
///
/// `kind == Added` and `hunks.size() == 1` are **deliberate narrowings, not
/// pinned invariants** -- dropping the kind check leaves the whole suite
/// green, which was measured rather than assumed. The reason is that every
/// other kind reachable here converges on the same end state under both
/// paths: a Modified or Deleted file's index entry is *restored to its HEAD
/// content* by either the reverse patch or `restore --staged`, rather than
/// emptied, so there is no orphan for this rule to clean up. A rename is not
/// a counter-example either -- workingTreeDiff is called with a single-path
/// pathspec, so git cannot pair the two halves and reports the new side as
/// Added anyway.
///
/// They stay because a narrowing that costs one `&&` is worth more than the
/// generality: this special case exists for exactly one measured shape, and
/// widening it silently would mean the next kind that *does* diverge gets
/// routed through `restore --staged` with no test noticing. Written down here
/// rather than left implied, because a future reader running the same
/// mutation will find it green and needs to know that is expected
/// ([CULT-scrutinise-the-comment] -- the comment is the thing to check).
///
/// An added file's diff has no context lines, so in practice every line here
/// is Added; the kind filter in the loop is written out anyway so the
/// predicate keeps meaning "every changed line" if that ever stops being true.
bool selectionCoversWholeAddedFile(const DiffFile& file,
                                   const DiffHunk& hunk,
                                   const std::vector<bool>& selected) {
    if (file.kind != FileChangeKind::Added || file.hunks.size() != 1) {
        return false;
    }
    for (std::size_t i = 0; i < hunk.lines.size(); ++i) {
        const DiffLineKind kind = hunk.lines[i].kind;
        if (kind != DiffLineKind::Added && kind != DiffLineKind::Removed) {
            continue;
        }
        if (i >= selected.size() || !selected[i]) {
            return false;
        }
    }
    return true;
}

/// `git restore --staged -- <path>`, the one end state a whole-file unstage
/// lands on. Shared so that UnstageFilesOperation and the whole-file case of
/// PartialStageOperation cannot drift into two different answers for the same
/// user-visible action ([CULT-single-source-of-truth]).
GitResult<ProcessResult> restoreStaged(IProcessRunner& runner,
                                       const RepoPaths& paths,
                                       const std::vector<std::string>& targets,
                                       CancellationToken token) {
    std::vector<std::string> args{"restore", "--staged", "--"};
    for (const std::string& path : targets) {
        args.push_back(path);
    }
    GitCommand command(paths.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);
    return runner.run(command, token);
}

class UnstageFilesOperation final : public Operation {
public:
    explicit UnstageFilesOperation(UnstageFilesRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.paths.size() == 1
                   ? "Unstage " + request_.paths.front()
                   : "Unstage " + std::to_string(request_.paths.size()) + " files";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.paths.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No files selected to unstage");
            return outcome;
        }

        auto result = restoreStaged(runner, paths, request_.paths, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    UnstageFilesRequest request_;
};

class ApplyPatchOperation final : public Operation {
public:
    explicit ApplyPatchOperation(ApplyPatchRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.reverse ? "Unstage selected changes" : "Stage selected changes";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.patch.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "Nothing to apply");
            return outcome;
        }

        auto result = applyPatchToIndex(runner, paths, request_.patch, request_.reverse, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    ApplyPatchRequest request_;
};

class PartialStageOperation final : public Operation {
public:
    explicit PartialStageOperation(PartialStageRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        const char* verb = request_.staged ? "Unstage " : "Stage ";
        const char* what = request_.lineIndices.empty() ? "hunk in " : "selected lines in ";
        return verb + std::string(what) + request_.path;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.path.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No file specified");
            return outcome;
        }

        DiffService diffs(runner, paths);
        const DiffOptions options;
        auto diffResult = diffs.workingTreeDiff(request_.staged, {request_.path}, options, token);
        if (!diffResult) {
            outcome.error = std::move(diffResult).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        const ParsedDiff& diff = *diffResult.value();
        if (diff.files.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "No pending changes found for \"" + request_.path + "\"");
            return outcome;
        }
        const DiffFile& file = diff.files.front();
        if (request_.hunkIndex >= file.hunks.size()) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "That change no longer exists -- the file may have changed");
            return outcome;
        }
        const DiffHunk& hunk = file.hunks[request_.hunkIndex];

        // An empty lineIndices means "the whole hunk", so every line in it is
        // selected -- built explicitly rather than special-cased below, so the
        // Added-file check reads the same selection the patch would.
        std::vector<bool> selected(hunk.lines.size(), request_.lineIndices.empty());
        if (!request_.lineIndices.empty()) {
            for (const std::size_t index : request_.lineIndices) {
                if (index < selected.size()) {
                    selected[index] = true;
                }
            }
        }

        // Unstaging every changed line of an added file cannot go through a
        // reverse patch: measured on git 2.55.0, `git apply --cached --reverse`
        // exits 0 and leaves the index entry in place holding the empty blob
        // e69de29, so porcelain still reports `A`/`AM` -- the file stays in the
        // Staged column reading +0 while also appearing under Unstaged.
        // `git rm --cached` was measured to be refused (exit 1) from that
        // state; `restore --staged` works and is what the whole-file unstage
        // path already runs, so both paths converge on one end state.
        if (request_.staged && selectionCoversWholeAddedFile(file, hunk, selected)) {
            auto restored = restoreStaged(runner, paths, {request_.path}, token);
            if (!restored) {
                outcome.error = std::move(restored).error();
                outcome.summary = outcome.error->message;
                return outcome;
            }
            outcome.succeeded = true;
            outcome.summary = describe();
            return outcome;
        }

        std::string patch;
        if (request_.lineIndices.empty()) {
            patch = UnifiedDiffParser::buildHunkPatch(
                file, hunk, /*reverse=*/false, /*unstaging=*/request_.staged);
        } else {
            patch = UnifiedDiffParser::buildLineSelectionPatch(
                file, hunk, selected, /*unstaging=*/request_.staged);
        }
        if (patch.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "Nothing selected to apply");
            return outcome;
        }

        auto result = applyPatchToIndex(runner, paths, patch, /*reverse=*/request_.staged, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    PartialStageRequest request_;
};

class DiscardLinesOperation final : public Operation {
public:
    explicit DiscardLinesOperation(DiscardLinesRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        const std::string what =
            request_.lineIndices.empty()
                ? "hunk in "
                : (request_.lineIndices.size() == 1
                       ? "1 line in "
                       : std::to_string(request_.lineIndices.size()) + " lines in ");
        return "Discard " + what + request_.path;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.path.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No file specified");
            return outcome;
        }

        // Always the *unstaged* diff (work tree vs index): discarding is only
        // ever defined against what the work tree has beyond the index.
        DiffService diffs(runner, paths);
        const DiffOptions options;
        auto diffResult = diffs.workingTreeDiff(/*staged=*/false, {request_.path}, options, token);
        if (!diffResult) {
            outcome.error = std::move(diffResult).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        const ParsedDiff& diff = *diffResult.value();
        if (diff.files.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "No pending changes found for \"" + request_.path + "\"");
            return outcome;
        }
        const DiffFile& file = diff.files.front();
        if (request_.hunkIndex >= file.hunks.size()) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "That change no longer exists -- the file may have changed");
            return outcome;
        }
        const DiffHunk& hunk = file.hunks[request_.hunkIndex];

        // `unstaging=true` even though nothing is being unstaged: that flag
        // means "this patch will be applied in reverse, so check it against
        // the new side", which is exactly what `git apply --reverse` does
        // here. It also keeps a rename's header pointed at the new path so
        // reversing the record discards the content change without undoing
        // the rename itself. See buildLineSelectionPatch's doc comment.
        std::string patch;
        if (request_.lineIndices.empty()) {
            patch = UnifiedDiffParser::buildHunkPatch(
                file, hunk, /*reverse=*/false, /*unstaging=*/true);
        } else {
            std::vector<bool> selected(hunk.lines.size(), false);
            for (const std::size_t index : request_.lineIndices) {
                if (index < selected.size()) {
                    selected[index] = true;
                }
            }
            patch = UnifiedDiffParser::buildLineSelectionPatch(
                file, hunk, selected, /*unstaging=*/true);
        }
        if (patch.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "Nothing selected to discard");
            return outcome;
        }

        auto result = applyPatch(runner, paths, patch, /*cached=*/false, /*reverse=*/true, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    DiscardLinesRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeStageFilesOperation(StageFilesRequest request) {
    return std::make_unique<StageFilesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeUnstageFilesOperation(UnstageFilesRequest request) {
    return std::make_unique<UnstageFilesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeApplyPatchOperation(ApplyPatchRequest request) {
    return std::make_unique<ApplyPatchOperation>(std::move(request));
}

std::unique_ptr<Operation> makePartialStageOperation(PartialStageRequest request) {
    return std::make_unique<PartialStageOperation>(std::move(request));
}

std::unique_ptr<Operation> makeDiscardLinesOperation(DiscardLinesRequest request) {
    return std::make_unique<DiscardLinesOperation>(std::move(request));
}

}  // namespace gbm
