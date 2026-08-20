#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/CatFileBatch.h"
#include "core/git/RepoPaths.h"

#include <cstdint>
#include <filesystem>
#include <string>

namespace gbm {

/// One "give me this file as it was at that commit" request, for context
/// menu 05-K's "Open file at this revision" / "Save this revision as...".
struct FileAtRevisionRequest {
    /// Any revision expression git accepts (`<oid>`, `HEAD~2`, a branch or
    /// tag name) -- it is spliced into `<revision>:<path>` unchanged.
    std::string revision;
    /// Repository-relative, forward-slashed, exactly as the changed-files
    /// list reports it.
    std::string path;
    /// Where the bytes are written. Nothing is created here unless the read
    /// succeeded, so a failed export never leaves a truncated file behind
    /// for the caller to hand to the OS.
    std::filesystem::path destination;
};

/// Reads a blob at a revision and writes it to a destination path.
///
/// Like CompareStore this is a plain store rather than an `Operation`
/// subclass: nothing in the repository changes, so there is no undo entry,
/// no refresh and no sequencer state to publish -- and like CompareStore it
/// is consumed through the capi layer's per-request "echo the query params
/// back" pattern, since several exports can be in flight at once.
///
/// **Why a destination path instead of returning the content**: both
/// callers need bytes on disk (one hands the path to the OS file
/// association, the other is a "save as"), and neither displays the content
/// in-app. Returning it inline would also mean a JSON string payload, which
/// cannot carry a binary blob at all -- an image recovered out of history is
/// exactly the case this has to support.
///
/// **Why CatFileBatch and not IProcessRunner** (this one is load-bearing,
/// and was found by measurement rather than by reading): `IProcessRunner::run()`
/// does not capture stdout verbatim. It reassembles the output from the line
/// splitter, which drops the final separator and strips a `\r` before every
/// `\n` for Windows CRLF tolerance -- so a text blob loses its trailing
/// newline and a binary blob is silently corrupted wherever `\r\n` occurs.
/// CatFileBatch reads exactly the byte count `cat-file --batch`'s header
/// declares, straight off the pipe, so it is binary-exact; it is also the
/// per-repository co-process docs/ARCHITECTURE.md already prescribes for
/// object reads, so this costs no extra process spawn.
class BlobStore {
public:
    BlobStore(std::filesystem::path gitExecutable, RepoPaths paths);
    ~BlobStore();

    BlobStore(const BlobStore&) = delete;
    BlobStore& operator=(const BlobStore&) = delete;

    /// The blob at `<revision>:<path>`, written verbatim to
    /// `request.destination`. Returns the number of bytes written.
    ///
    /// CatFileBatch applies its own upper bound on object size and reports
    /// it as a readable error rather than truncating (the "every cap is
    /// visible" rule from docs/ARCHITECTURE.md), so there is no second cap
    /// here.
    GitResult<std::uint64_t> exportFileAtRevision(FileAtRevisionRequest request,
                                                  CancellationToken token);

    /// Stops the underlying `cat-file --batch` child. Not required before
    /// destruction -- mirrors CommitMetaStore::stop()'s contract exactly.
    void stop();

private:
    CatFileBatch batch_;
};

}  // namespace gbm
