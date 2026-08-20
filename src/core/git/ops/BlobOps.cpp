#include "core/git/ops/BlobOps.h"

#include <fstream>
#include <system_error>
#include <utility>

namespace gbm {

BlobStore::BlobStore(std::filesystem::path gitExecutable, RepoPaths paths)
    : batch_(std::move(gitExecutable), std::move(paths)) {}

BlobStore::~BlobStore() = default;

GitResult<std::uint64_t> BlobStore::exportFileAtRevision(FileAtRevisionRequest request,
                                                         CancellationToken token) {
    if (request.revision.empty() || request.path.empty() || request.destination.empty()) {
        return fail(GitError::Code::InvalidArgument,
                    "A revision, a path and a destination are all required");
    }

    // git's own "this file at that commit" syntax. Not quoted or escaped:
    // CatFileBatch writes it as one protocol line and rejects an embedded
    // newline itself, and no shell is ever involved.
    const std::string spec = request.revision + ":" + request.path;
    const GitResult<CatFileBatch::Object> object = batch_.read(spec, token);
    if (!object) {
        // Kept as git classified it (NotFound for a path absent at that
        // revision, which is an ordinary outcome), but reworded to name what
        // the user actually asked for -- git's own message talks about
        // objects, which means nothing next to a file row.
        GitError error = object.error();
        if (error.code == GitError::Code::NotFound) {
            error.message = "'" + request.path + "' is not a file at " + request.revision;
        }
        return Unexpected<GitError>(std::move(error));
    }

    // `<rev>:<dir>` resolves to a tree, which is a perfectly valid object and
    // therefore not caught above -- but it is not a file, and writing a tree
    // listing out under the user's chosen filename would be worse than
    // refusing.
    if (object->type != "blob") {
        return fail(GitError::Code::InvalidArgument,
                    "'" + request.path + "' is a " + object->type + " at " + request.revision +
                        ", not a file");
    }

    std::ofstream out(request.destination, std::ios::binary | std::ios::trunc);
    if (!out) {
        return fail(GitError::Code::Io,
                    "Could not open '" + request.destination.string() + "' for writing");
    }
    out.write(object->content.data(), static_cast<std::streamsize>(object->content.size()));
    out.close();
    if (!out) {
        // A partially written file is worse than none: the caller would hand
        // the OS a truncated image, or save a corrupt copy over a good one.
        std::error_code ec;
        std::filesystem::remove(request.destination, ec);
        return fail(GitError::Code::Io, "Could not write '" + request.destination.string() + "'");
    }
    return static_cast<std::uint64_t>(object->content.size());
}

void BlobStore::stop() {
    batch_.stop();
}

}  // namespace gbm
