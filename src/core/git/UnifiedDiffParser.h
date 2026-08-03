#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace gbm {

enum class DiffLineKind : std::uint8_t {
    Context,
    Added,
    Removed,
    NoNewlineMarker,  ///< "\ No newline at end of file"
};

struct DiffLine {
    DiffLineKind kind = DiffLineKind::Context;
    std::uint32_t oldLine = 0;  ///< 1-based; 0 when the line has no old side.
    std::uint32_t newLine = 0;  ///< 1-based; 0 when the line has no new side.
    std::string text;           ///< Without the leading +/-/space marker.
};

struct DiffHunk {
    std::uint32_t oldStart = 0;
    std::uint32_t oldCount = 0;
    std::uint32_t newStart = 0;
    std::uint32_t newCount = 0;
    std::string heading;  ///< The function context after the @@ marker.
    std::vector<DiffLine> lines;
};

enum class FileChangeKind : std::uint8_t {
    Modified,
    Added,
    Deleted,
    Renamed,
    Copied,
    TypeChanged,
    ModeChanged,
};

struct DiffFile {
    std::string oldPath;
    std::string newPath;
    FileChangeKind kind = FileChangeKind::Modified;
    std::string oldMode;
    std::string newMode;
    std::string oldBlob;  ///< Abbreviated oid from the index line.
    std::string newBlob;
    bool binary = false;
    int similarity = 0;  ///< Percentage, for renames and copies.
    std::vector<DiffHunk> hunks;

    std::uint32_t addedLines = 0;
    std::uint32_t removedLines = 0;

    /// The path to show in the UI: the new path unless the file was deleted.
    const std::string& displayPath() const {
        return kind == FileChangeKind::Deleted ? oldPath : newPath;
    }
};

struct ParsedDiff {
    std::vector<DiffFile> files;
    bool truncated = false;  ///< Input exceeded the size cap.
    std::size_t inputBytes = 0;
};

/// Parses git's unified diff output into structured hunks.
///
/// This parser exists because the backend is the git CLI: with no in-process diff
/// library, `git diff -p` text is the only source of hunk data. It is therefore
/// new surface area, and a bug here shows up as a *wrong diff* rather than a
/// crash — which is why it gets golden tests over every awkward case: binary
/// files, mode-only changes, renames, missing trailing newlines, CRLF, empty
/// hunks and combined merge diffs.
class UnifiedDiffParser {
public:
    struct Options {
        /// Diffs beyond this are reported as truncated rather than parsed. A
        /// generated 40 MB file must not be turned into millions of DiffLine
        /// objects just because it was clicked on.
        std::size_t maxBytes = 2u * 1024u * 1024u;

        /// Lines longer than this are clipped. Minified JavaScript arrives as one
        /// 3 MB line and would otherwise stall the renderer.
        std::size_t maxLineLength = 8u * 1024u;
    };

    UnifiedDiffParser() = default;

    explicit UnifiedDiffParser(Options options) : options_(options) {}

    ParsedDiff parse(std::string_view diffText) const;

    /// Reconstructs a patch for a single hunk, suitable for piping to
    /// `git apply --cached`. Used for hunk-level staging, where applying against
    /// blob content (rather than the file on disk) is what keeps CRLF and
    /// smudge/clean filters from corrupting the result.
    ///
    /// `unstaging` has the same meaning and rationale as the parameter of the
    /// same name on `buildLineSelectionPatch` below: it does not touch line
    /// markers or the hunk header (that is still `reverse`'s job, and callers
    /// normally leave it false and let `git apply --reverse` do the flip
    /// instead). It only controls whether a rename/copy is described in the
    /// header -- pass `true` when this hunk is being unstaged from a diff
    /// where the file is a rename, so a patch applied with `--reverse` doesn't
    /// undo the rename along with the content. See `buildLineSelectionPatch`'s
    /// doc comment for the full explanation of why staging and unstaging need
    /// different headers for a renamed file.
    static std::string buildHunkPatch(const DiffFile& file,
                                      const DiffHunk& hunk,
                                      bool reverse = false,
                                      bool unstaging = false);

    /// Reconstructs a patch that applies only a subset of a hunk's added and
    /// removed lines, for line-level staging or unstaging.
    ///
    /// `selected[i]` says whether `hunk.lines[i]` should take effect; it is
    /// ignored for context and no-newline-marker lines, which always pass
    /// through.
    ///
    /// `unstaging` is *not* the same kind of flag as `buildHunkPatch`'s
    /// `reverse` above — that one swaps the hunk-header ranges because its
    /// caller passes the result straight to `git apply` in the forward
    /// direction. Here the header always stays forward: `StageOps` is the one
    /// that passes `--reverse` to `git apply --cached`, and doubling that
    /// reversal here would cancel it out. What `unstaging` actually changes is
    /// which *unselected* lines become context vs. get dropped, because the
    /// two directions check the patch against different things:
    ///
    /// - Staging (`git apply --cached`) checks the patch's *old* side against
    ///   the index. An unselected added line was never staged, so it is
    ///   dropped; an unselected removed line survives, so it is kept as
    ///   context.
    /// - Unstaging (`git apply --cached --reverse`) checks the patch's *new*
    ///   side against the index instead. An unselected added line *is* in the
    ///   index and must stay, so it becomes context; an unselected removed
    ///   line never was in the index, so it is dropped. Getting this backwards
    ///   is exactly what used to make partial-selection unstage fail with
    ///   "patch does not apply" — the reconstructed new side did not equal
    ///   the actual index content.
    ///
    /// For a renamed/copied file, `unstaging` also drops the `rename from`/
    /// `rename to` header and points both sides at the new path instead:
    /// `git apply --cached --reverse` reverses the whole patch record, header
    /// included, so a patch built the same way for both directions would undo
    /// the rename itself on unstage, not just the selected lines. By the time
    /// a rename's content is being unstaged the rename is already in the
    /// index, so the reconstructed patch only needs to describe a same-path
    /// content change.
    static std::string buildLineSelectionPatch(const DiffFile& file,
                                               const DiffHunk& hunk,
                                               const std::vector<bool>& selected,
                                               bool unstaging = false);

private:
    Options options_{};
};

}  // namespace gbm
