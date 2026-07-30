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
    static std::string buildHunkPatch(const DiffFile& file,
                                      const DiffHunk& hunk,
                                      bool reverse = false);

private:
    Options options_{};
};

}  // namespace gbm
