#include "core/git/UnifiedDiffParser.h"

#include <algorithm>
#include <charconv>

namespace gbm {

namespace {

/// Splits on '\n' and strips a trailing '\r'. Diff payload lines keep their
/// content verbatim otherwise, because a diff of a file with mixed line endings
/// must not be silently normalised.
std::vector<std::string_view> splitLines(std::string_view text) {
    std::vector<std::string_view> lines;
    std::size_t start = 0;
    while (start <= text.size()) {
        const std::size_t at = text.find('\n', start);
        if (at == std::string_view::npos) {
            if (start < text.size()) {
                lines.push_back(text.substr(start));
            }
            break;
        }
        std::string_view line = text.substr(start, at - start);
        if (!line.empty() && line.back() == '\r') {
            line.remove_suffix(1);
        }
        lines.push_back(line);
        start = at + 1;
    }
    return lines;
}

/// Writes the `diff --git`/`--- `/`+++ ` header block used by both
/// buildHunkPatch and buildLineSelectionPatch, including `rename from`/
/// `rename to` (or `copy from`/`copy to`) when `file` is one -- without them,
/// `git apply` has no way to associate the hunk with a file whose path
/// changed, since `--- a/oldPath` alone reads as "this file still exists at
/// oldPath", which a rename makes untrue.
///
/// `unstaging` suppresses the rename/copy metadata and points both sides of
/// the header at `newPath`. `git apply --cached --reverse` reverses the
/// *entire* patch record, `rename from`/`rename to` included -- so a header
/// built the same way for staging and unstaging would, on unstage, undo the
/// rename itself rather than just the selected content. By the time a rename
/// is being unstaged, the index already has the file at `newPath` (the rename
/// was staged first); the reconstructed patch only needs to describe a
/// content change at that path, which content-only, same-path headers do
/// without touching the rename that already landed.
///
/// A file with no old side -- `FileChangeKind::Added` -- needs `new file mode`
/// and `--- /dev/null` written back out when the patch is being *staged*, and
/// `git apply --cached` refuses it otherwise: measured, `error: <path>: does
/// not exist in index`, exit 1. That is how an untracked file's selected lines
/// reach the index, and it is why the mode falls back to 100644 rather than
/// being omitted -- `git apply` reads the `new file mode` line, not the
/// `index` line, to decide it is creating a file.
///
/// **The condition is `kind`, not an empty `oldPath`.** `--- /dev/null` does
/// strip to an empty string, but the `diff --git a/x b/x` line has already
/// filled `oldPath` in by then and the `---` handler declines to overwrite it
/// with nothing, so an added file's `oldPath` is its own path -- a plausible
/// -looking test of "has no old side" that is never true.
///
/// **Unstaging is deliberately left alone**: by then the file is in the index,
/// `git apply --cached --reverse` checks the patch's *new* side against it,
/// and the plain `a/<path>` header is what matches -- measured to apply
/// cleanly. An intent-to-add path (`git add -N`, which `git diff` also reports
/// as `new file mode`) accepts the create form on the staging side too:
/// measured, exit 0, landing as `AM`.
void appendPatchHeader(std::string& patch,
                       const DiffFile& file,
                       const std::string& oldPath,
                       const std::string& newPath,
                       bool unstaging) {
    const bool isRenameOrCopy =
        (file.kind == FileChangeKind::Renamed || file.kind == FileChangeKind::Copied) &&
        oldPath != newPath;
    const bool contentOnlyAtNewPath = unstaging && isRenameOrCopy;
    const std::string& headerOldPath = contentOnlyAtNewPath ? newPath : oldPath;

    if (!unstaging && file.kind == FileChangeKind::Added) {
        patch += "diff --git a/" + newPath + " b/" + newPath + "\n";
        patch +=
            "new file mode " + (file.newMode.empty() ? std::string("100644") : file.newMode) + "\n";
        patch += "--- /dev/null\n";
        patch += "+++ b/" + newPath + "\n";
        return;
    }

    patch += "diff --git a/" + headerOldPath + " b/" + newPath + "\n";
    if (isRenameOrCopy && !contentOnlyAtNewPath) {
        patch += "similarity index " + std::to_string(file.similarity) + "%\n";
        patch +=
            (file.kind == FileChangeKind::Renamed ? "rename from " : "copy from ") + oldPath + "\n";
        patch +=
            (file.kind == FileChangeKind::Renamed ? "rename to " : "copy to ") + newPath + "\n";
    }
    patch += "--- a/" + headerOldPath + "\n";
    patch += "+++ b/" + newPath + "\n";
}

std::uint32_t parseUint(std::string_view text) {
    std::uint32_t value = 0;
    std::from_chars(text.data(), text.data() + text.size(), value);
    return value;
}

/// Unquotes a path from a `diff --git` header. git quotes paths containing
/// unusual bytes even with core.quotepath=false (double quotes, control chars).
std::string unquotePath(std::string_view raw) {
    if (raw.size() < 2 || raw.front() != '"' || raw.back() != '"') {
        return std::string(raw);
    }
    std::string_view inner = raw.substr(1, raw.size() - 2);
    std::string out;
    out.reserve(inner.size());
    for (std::size_t i = 0; i < inner.size(); ++i) {
        if (inner[i] != '\\' || i + 1 >= inner.size()) {
            out.push_back(inner[i]);
            continue;
        }
        const char escape = inner[++i];
        switch (escape) {
            case 'n':
                out.push_back('\n');
                break;
            case 't':
                out.push_back('\t');
                break;
            case 'r':
                out.push_back('\r');
                break;
            case '"':
                out.push_back('"');
                break;
            case '\\':
                out.push_back('\\');
                break;
            default:
                // Octal escape, e.g. \303\251 for a UTF-8 byte pair.
                if (escape >= '0' && escape <= '7') {
                    int value = escape - '0';
                    for (int digit = 0; digit < 2 && i + 1 < inner.size() && inner[i + 1] >= '0' &&
                                        inner[i + 1] <= '7';
                         ++digit) {
                        value = value * 8 + (inner[++i] - '0');
                    }
                    out.push_back(static_cast<char>(value));
                } else {
                    out.push_back(escape);
                }
                break;
        }
    }
    return out;
}

/// Strips git's a/ or b/ prefix. Handles /dev/null, which carries no prefix.
std::string stripPathPrefix(std::string_view path) {
    if (path == "/dev/null") {
        return {};
    }
    if (path.size() > 2 && (path[0] == 'a' || path[0] == 'b') && path[1] == '/') {
        return std::string(path.substr(2));
    }
    return std::string(path);
}

}  // namespace

ParsedDiff UnifiedDiffParser::parse(std::string_view diffText) const {
    ParsedDiff parsed;
    parsed.inputBytes = diffText.size();

    if (diffText.size() > options_.maxBytes) {
        // Refused, not truncated-and-shown. Parsing the first maxBytes used to
        // hand back a diff that looked complete and was not -- the tail was
        // dropped with nothing on screen saying so, which is a wrong diff
        // rather than a missing one. `truncated` is the whole answer now, and
        // every consumer owes the user a message for it.
        parsed.truncated = true;
        return parsed;
    }

    const auto lines = splitLines(diffText);
    DiffFile* file = nullptr;
    DiffHunk* hunk = nullptr;
    std::uint32_t oldLine = 0;
    std::uint32_t newLine = 0;

    auto finishFile = [&parsed, &file, &hunk] {
        (void)parsed;
        file = nullptr;
        hunk = nullptr;
    };

    for (std::size_t index = 0; index < lines.size(); ++index) {
        std::string_view line = lines[index];

        // --- new file section ------------------------------------------------
        if (line.rfind("diff --git ", 0) == 0) {
            finishFile();
            parsed.files.emplace_back();
            file = &parsed.files.back();

            // "diff --git a/old b/new". Paths may contain spaces, so prefer the
            // explicit ---/+++ lines below; this is only a fallback for headers
            // with no hunks (mode changes, binary files).
            std::string_view rest = line.substr(11);
            const std::size_t bAt = rest.rfind(" b/");
            if (bAt != std::string_view::npos) {
                file->oldPath = stripPathPrefix(unquotePath(rest.substr(0, bAt)));
                file->newPath = stripPathPrefix(unquotePath(rest.substr(bAt + 1)));
            }
            continue;
        }

        if (file == nullptr) {
            continue;  // Preamble before the first file header.
        }

        // --- extended headers ------------------------------------------------
        if (line.rfind("old mode ", 0) == 0) {
            file->oldMode = std::string(line.substr(9));
            file->kind = FileChangeKind::ModeChanged;
            continue;
        }
        if (line.rfind("new mode ", 0) == 0) {
            file->newMode = std::string(line.substr(9));
            continue;
        }
        if (line.rfind("new file mode ", 0) == 0) {
            file->newMode = std::string(line.substr(14));
            file->kind = FileChangeKind::Added;
            continue;
        }
        if (line.rfind("deleted file mode ", 0) == 0) {
            file->oldMode = std::string(line.substr(18));
            file->kind = FileChangeKind::Deleted;
            continue;
        }
        if (line.rfind("rename from ", 0) == 0) {
            file->oldPath = unquotePath(line.substr(12));
            file->kind = FileChangeKind::Renamed;
            continue;
        }
        if (line.rfind("rename to ", 0) == 0) {
            file->newPath = unquotePath(line.substr(10));
            file->kind = FileChangeKind::Renamed;
            continue;
        }
        if (line.rfind("copy from ", 0) == 0) {
            file->oldPath = unquotePath(line.substr(10));
            file->kind = FileChangeKind::Copied;
            continue;
        }
        if (line.rfind("copy to ", 0) == 0) {
            file->newPath = unquotePath(line.substr(8));
            file->kind = FileChangeKind::Copied;
            continue;
        }
        if (line.rfind("similarity index ", 0) == 0) {
            file->similarity = static_cast<int>(parseUint(line.substr(17)));
            continue;
        }
        if (line.rfind("index ", 0) == 0) {
            // "index <old>..<new> <mode>"
            std::string_view rest = line.substr(6);
            const std::size_t dots = rest.find("..");
            if (dots != std::string_view::npos) {
                file->oldBlob = std::string(rest.substr(0, dots));
                std::string_view after = rest.substr(dots + 2);
                const std::size_t space = after.find(' ');
                file->newBlob =
                    std::string(space == std::string_view::npos ? after : after.substr(0, space));
                if (space != std::string_view::npos && file->newMode.empty()) {
                    file->newMode = std::string(after.substr(space + 1));
                }
            }
            continue;
        }
        if (line.rfind("Binary files ", 0) == 0 || line.rfind("GIT binary patch", 0) == 0) {
            // No hunks will follow; the UI offers to open the file instead.
            file->binary = true;
            continue;
        }
        if (line.rfind("--- ", 0) == 0) {
            const std::string path = stripPathPrefix(unquotePath(line.substr(4)));
            if (!path.empty()) {
                file->oldPath = path;
            }
            continue;
        }
        if (line.rfind("+++ ", 0) == 0) {
            const std::string path = stripPathPrefix(unquotePath(line.substr(4)));
            if (!path.empty()) {
                file->newPath = path;
            }
            continue;
        }

        // --- hunk header -----------------------------------------------------
        if (line.rfind("@@", 0) == 0) {
            // "@@ -oldStart,oldCount +newStart,newCount @@ heading"
            // A combined merge diff uses "@@@ -a,b -c,d +e,f @@@": take the last
            // '-' range as the old side so the first-parent view still renders.
            const std::size_t closing = line.find("@@", 2);
            if (closing == std::string_view::npos) {
                continue;
            }
            std::string_view ranges = line.substr(2, closing - 2);

            file->hunks.emplace_back();
            hunk = &file->hunks.back();
            if (closing + 2 < line.size()) {
                std::string_view heading = line.substr(closing + 2);
                while (!heading.empty() && heading.front() == ' ') {
                    heading.remove_prefix(1);
                }
                hunk->heading = std::string(heading);
            }

            std::size_t cursor = 0;
            auto readRange = [&ranges, &cursor](
                                 char sign, std::uint32_t* start, std::uint32_t* count) {
                const std::size_t at = ranges.find(sign, cursor);
                if (at == std::string_view::npos) {
                    return false;
                }
                cursor = at + 1;
                std::size_t end = cursor;
                while (end < ranges.size() && ranges[end] != ' ') {
                    ++end;
                }
                std::string_view text = ranges.substr(cursor, end - cursor);
                const std::size_t comma = text.find(',');
                if (comma == std::string_view::npos) {
                    *start = parseUint(text);
                    *count = 1;  // Omitted count means exactly one line.
                } else {
                    *start = parseUint(text.substr(0, comma));
                    *count = parseUint(text.substr(comma + 1));
                }
                cursor = end;
                return true;
            };

            // Consume every '-' range; the last one wins (combined diffs).
            while (readRange('-', &hunk->oldStart, &hunk->oldCount)) {
            }
            cursor = 0;
            readRange('+', &hunk->newStart, &hunk->newCount);

            oldLine = hunk->oldStart;
            newLine = hunk->newStart;
            continue;
        }

        // --- hunk body -------------------------------------------------------
        if (hunk == nullptr) {
            continue;
        }
        if (line.rfind("\\ No newline", 0) == 0) {
            DiffLine marker;
            marker.kind = DiffLineKind::NoNewlineMarker;
            marker.text = std::string(line);
            hunk->lines.push_back(std::move(marker));
            continue;
        }

        DiffLine diffLine;
        const char marker = line.empty() ? ' ' : line.front();
        std::string_view content = line.empty() ? line : line.substr(1);
        if (content.size() > options_.maxLineLength) {
            content = content.substr(0, options_.maxLineLength);
        }

        switch (marker) {
            case '+':
                diffLine.kind = DiffLineKind::Added;
                diffLine.newLine = newLine++;
                ++file->addedLines;
                break;
            case '-':
                diffLine.kind = DiffLineKind::Removed;
                diffLine.oldLine = oldLine++;
                ++file->removedLines;
                break;
            case ' ':
                diffLine.kind = DiffLineKind::Context;
                diffLine.oldLine = oldLine++;
                diffLine.newLine = newLine++;
                break;
            default:
                // Not part of a hunk (a trailing "-- " signature line, or the
                // start of the next section). Leave the hunk and reprocess.
                hunk = nullptr;
                --index;
                continue;
        }
        diffLine.text = std::string(content);
        hunk->lines.push_back(std::move(diffLine));
    }

    return parsed;
}

std::string UnifiedDiffParser::buildHunkPatch(const DiffFile& file,
                                              const DiffHunk& hunk,
                                              bool reverse,
                                              bool unstaging) {
    // A minimal single-hunk patch. `git apply` needs the file headers even for one
    // hunk, and the counts must match the emitted lines exactly or it refuses.
    const std::string& oldPath = file.oldPath.empty() ? file.newPath : file.oldPath;
    const std::string& newPath = file.newPath.empty() ? file.oldPath : file.newPath;

    std::uint32_t oldCount = 0;
    std::uint32_t newCount = 0;
    for (const DiffLine& line : hunk.lines) {
        switch (line.kind) {
            case DiffLineKind::Context:
                ++oldCount;
                ++newCount;
                break;
            case DiffLineKind::Added:
                ++newCount;
                break;
            case DiffLineKind::Removed:
                ++oldCount;
                break;
            case DiffLineKind::NoNewlineMarker:
                break;
        }
    }

    std::string patch;
    appendPatchHeader(patch, file, oldPath, newPath, unstaging);
    // Reversing a patch swaps the two sides, not just the line markers: emitting
    // flipped signs against the original ranges produces a patch git rejects.
    // (Callers may instead keep reverse=false and pass `git apply --reverse`.)
    if (reverse) {
        patch += "@@ -" + std::to_string(hunk.newStart) + "," + std::to_string(newCount) + " +" +
                 std::to_string(hunk.oldStart) + "," + std::to_string(oldCount) + " @@\n";
    } else {
        patch += "@@ -" + std::to_string(hunk.oldStart) + "," + std::to_string(oldCount) + " +" +
                 std::to_string(hunk.newStart) + "," + std::to_string(newCount) + " @@\n";
    }

    for (const DiffLine& line : hunk.lines) {
        switch (line.kind) {
            case DiffLineKind::Context:
                patch += " " + line.text + "\n";
                break;
            case DiffLineKind::Added:
                patch += (reverse ? "-" : "+") + line.text + "\n";
                break;
            case DiffLineKind::Removed:
                patch += (reverse ? "+" : "-") + line.text + "\n";
                break;
            case DiffLineKind::NoNewlineMarker:
                patch += "\\ No newline at end of file\n";
                break;
        }
    }
    return patch;
}

std::string UnifiedDiffParser::buildLineSelectionPatch(const DiffFile& file,
                                                       const DiffHunk& hunk,
                                                       const std::vector<bool>& selected,
                                                       bool unstaging) {
    const std::string& oldPath = file.oldPath.empty() ? file.newPath : file.oldPath;
    const std::string& newPath = file.newPath.empty() ? file.oldPath : file.newPath;

    struct EmittedLine {
        char marker;
        const std::string* text;
    };

    std::vector<EmittedLine> body;
    body.reserve(hunk.lines.size());

    // Whether the line immediately before the current position was actually
    // emitted into `body` (as opposed to dropped) -- a NoNewlineMarker only
    // makes sense following a line that is actually present in the patch;
    // emitting it after a dropped line produces a patch `git apply` rejects.
    bool previousLineEmitted = false;

    for (std::size_t i = 0; i < hunk.lines.size(); ++i) {
        const DiffLine& line = hunk.lines[i];
        const bool isSelected = i < selected.size() && selected[i];
        switch (line.kind) {
            case DiffLineKind::Context:
                body.push_back({' ', &line.text});
                previousLineEmitted = true;
                break;
            case DiffLineKind::Added:
                if (isSelected) {
                    // Selected: stays added either way -- staging it adds it,
                    // unstaging it takes it back out of the index.
                    body.push_back({'+', &line.text});
                    previousLineEmitted = true;
                } else if (unstaging) {
                    // Unstaging: an unselected added line *is* already in the
                    // index (that is what "staged" means), and must stay
                    // there -- from the reverse patch's point of view it is
                    // unchanged context, not something to drop.
                    body.push_back({' ', &line.text});
                    previousLineEmitted = true;
                } else {
                    // Staging: an unselected added line was never staged, so
                    // it is simply omitted rather than turned into context.
                    previousLineEmitted = false;
                }
                break;
            case DiffLineKind::Removed:
                if (isSelected) {
                    // Selected: stays removed either way -- staging it
                    // removes it, unstaging it puts it back in the index.
                    body.push_back({'-', &line.text});
                    previousLineEmitted = true;
                } else if (unstaging) {
                    // Unstaging: an unselected removed line was never in the
                    // index to begin with (only a selected removal would
                    // have staged its removal), so it is omitted here too --
                    // the opposite of the staging case below.
                    previousLineEmitted = false;
                } else {
                    // Staging: an unselected removed line is not being
                    // removed, so from the patch's point of view it survives
                    // unchanged.
                    body.push_back({' ', &line.text});
                    previousLineEmitted = true;
                }
                break;
            case DiffLineKind::NoNewlineMarker:
                if (previousLineEmitted) {
                    body.push_back({'\\', &line.text});
                }
                break;
        }
    }

    // Counts are derived from what was actually emitted, not recomputed from
    // `DiffLineKind` in a second pass that could drift out of sync with the
    // selection logic above -- that mismatch is exactly the bug class that
    // produces git's "patch does not apply".
    std::uint32_t oldCount = 0;
    std::uint32_t newCount = 0;
    for (const EmittedLine& emitted : body) {
        switch (emitted.marker) {
            case ' ':
                ++oldCount;
                ++newCount;
                break;
            case '+':
                ++newCount;
                break;
            case '-':
                ++oldCount;
                break;
            default:
                break;  // '\\': annotates the previous line, adds no line of its own.
        }
    }

    std::string patch;
    appendPatchHeader(patch, file, oldPath, newPath, unstaging);
    patch += "@@ -" + std::to_string(hunk.oldStart) + "," + std::to_string(oldCount) + " +" +
             std::to_string(hunk.newStart) + "," + std::to_string(newCount) + " @@\n";

    for (const EmittedLine& emitted : body) {
        if (emitted.marker == '\\') {
            patch += "\\ No newline at end of file\n";
        } else {
            patch += emitted.marker + *emitted.text + "\n";
        }
    }
    return patch;
}

}  // namespace gbm
