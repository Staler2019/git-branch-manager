#pragma once

#include "core/base/ObjectId.h"
#include "core/git/OperationRunner.h"

#include <filesystem>
#include <memory>
#include <vector>

namespace gbm {

struct ExportPatchesRequest {
    /// Oldest first, same convention as CherryPickRequest::commits -- a single
    /// commit is a one-element list, a range is this same list after the
    /// caller has expanded it with RefStore::resolveRange.
    std::vector<ObjectId> commits;
    std::filesystem::path outputDir;
};

/// `git format-patch -1 <commit> --start-number <n> -o <dir>`, once per commit
/// in order. One call per commit rather than a single range invocation, so an
/// arbitrary (not necessarily contiguous) selection can be exported exactly
/// like it can be cherry-picked; `--start-number` keeps the filenames in the
/// caller's order instead of each call resetting to 0001 and overwriting the
/// last one.
std::unique_ptr<Operation> makeExportPatchesOperation(ExportPatchesRequest request);

struct ApplyPatchFilesRequest {
    std::vector<std::filesystem::path> patchFiles;
    /// `--3way`: falls back to a merge (leaving conflict markers) instead of
    /// refusing outright when the patch does not apply cleanly.
    bool threeWay = false;
    /// `--index`: also stages the result, not just the work tree.
    bool updateIndex = false;
};

/// `git apply`: applies a plain diff without creating a commit. For a patch
/// produced by `format-patch` and its commit metadata, see the `am` family
/// below instead.
std::unique_ptr<Operation> makeApplyPatchFilesOperation(ApplyPatchFilesRequest request);

struct ImportPatchesRequest {
    std::vector<std::filesystem::path> patchFiles;
    /// `--3way`: same fallback as ApplyPatchFilesRequest::threeWay.
    bool threeWay = false;
};

/// `git am`: applies one or more `format-patch`-style patches as commits,
/// preserving author, date and message. Like `rebase`/`cherry-pick`, a patch
/// that does not apply stops the sequence; see makeAmContinueOperation et al.
/// `git am` shares its on-disk state directory with the old-style
/// `rebase --apply` backend (RepoState::RebaseApply covers both), but the two
/// are not interchangeable: continuing an `am` needs `git am --continue`, not
/// `git rebase --continue`, so it gets its own continue/skip/abort here rather
/// than reusing RebaseOps.
std::unique_ptr<Operation> makeImportPatchesOperation(ImportPatchesRequest request);

/// `git am --continue`, once the conflicted patch's resolution is staged.
std::unique_ptr<Operation> makeAmContinueOperation();

/// `git am --skip`: drops the current patch and moves on to the next queued.
std::unique_ptr<Operation> makeAmSkipOperation();

/// `git am --abort`: unwinds back to before the patch series started.
std::unique_ptr<Operation> makeAmAbortOperation();

}  // namespace gbm
