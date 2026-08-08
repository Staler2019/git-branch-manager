#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace gbm {

enum class ConflictSegmentKind : std::uint8_t { Text, Region };

/// One stretch of a conflict-marked file: either plain text carried through
/// unchanged, or one <<<<<<</=======/>>>>>>> conflict region. Each line string
/// keeps its own trailing line ending ("foo\n" or "foo\r\n"; a file's last
/// line has none if the file itself has no trailing newline), so re-assembly
/// is pure concatenation -- CRLF and a missing final newline are preserved by
/// construction, not by a post-hoc replace() over the whole buffer.
struct ConflictSegment {
    ConflictSegmentKind kind = ConflictSegmentKind::Text;
    std::vector<std::string> lines;   ///< Text segments only.
    std::vector<std::string> ours;    ///< Region: stage 2 (HEAD) side.
    std::vector<std::string> theirs;  ///< Region: stage 3 (incoming) side.
    std::vector<std::string> base;    ///< Region: diff3 ||||||| side, if present.
    bool hasBase = false;
};

struct ParsedConflictFile {
    std::vector<ConflictSegment> segments;
    std::size_t regionCount = 0;
    /// False when a `<<<<<<<` line was never matched by a `>>>>>>>` before
    /// EOF. Rather than guess at a malformed split, the whole file is then
    /// kept as a single, untouched Text segment (regionCount == 0) -- the
    /// caller's existing whole-file take-left/take-right path already covers
    /// this degraded case.
    bool wellFormed = true;
};

enum class ConflictRegionChoice : std::uint8_t { Unresolved, Ours, Theirs, Custom };

struct ConflictRegionResolution {
    ConflictRegionChoice choice = ConflictRegionChoice::Unresolved;
    std::vector<std::string> customLines;  ///< Choice == Custom only.
};

/// Splits a working-tree file's raw content (conflict markers and all) into
/// plain-text and per-region segments, and reassembles a chosen resolution
/// back into plain text that can never contain a literal marker line -- the
/// marker lines themselves are consumed while parsing and never stored in
/// any segment, so nothing downstream can accidentally echo them back out.
class ConflictMarkerParser {
public:
    ParsedConflictFile parse(std::string_view content) const;

    /// nullopt if resolutions.size() != parsed.regionCount, or any entry is
    /// still Unresolved -- callers gate "Save" on every region having a
    /// choice, so assembling a partial resolution is always a caller bug
    /// rather than a state to render.
    static std::optional<std::string> assemble(
        const ParsedConflictFile& parsed,
        const std::vector<ConflictRegionResolution>& resolutions);
};

}  // namespace gbm
