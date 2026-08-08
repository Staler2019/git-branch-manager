#include "core/git/ConflictMarkerParser.h"

namespace gbm {

namespace {

/// Splits `content` into lines, each keeping its own trailing line ending
/// ("foo\n" / "foo\r\n"); the final line has none if the file itself has no
/// trailing newline. Reassembly is then pure concatenation, so callers never
/// need to guess at (or normalise away) line endings.
std::vector<std::string> splitKeepingLineEndings(std::string_view content) {
    std::vector<std::string> lines;
    std::size_t start = 0;
    while (start < content.size()) {
        const std::size_t newlinePos = content.find('\n', start);
        if (newlinePos == std::string_view::npos) {
            lines.emplace_back(content.substr(start));
            break;
        }
        lines.emplace_back(content.substr(start, newlinePos - start + 1));
        start = newlinePos + 1;
    }
    return lines;
}

/// A line's content with any trailing "\r\n" or "\n" removed, for comparing
/// against marker text without the line ending getting in the way.
std::string_view stripLineEnding(const std::string& line) {
    std::string_view view(line);
    if (!view.empty() && view.back() == '\n') {
        view.remove_suffix(1);
    }
    if (!view.empty() && view.back() == '\r') {
        view.remove_suffix(1);
    }
    return view;
}

}  // namespace

ParsedConflictFile ConflictMarkerParser::parse(std::string_view content) const {
    const std::vector<std::string> lines = splitKeepingLineEndings(content);

    ParsedConflictFile result;
    std::vector<std::string> pendingText;
    auto flushText = [&] {
        if (pendingText.empty()) {
            return;
        }
        ConflictSegment segment;
        segment.kind = ConflictSegmentKind::Text;
        segment.lines = std::move(pendingText);
        result.segments.push_back(std::move(segment));
        pendingText.clear();
    };

    std::size_t i = 0;
    while (i < lines.size()) {
        if (!stripLineEnding(lines[i]).starts_with("<<<<<<<")) {
            pendingText.push_back(lines[i]);
            ++i;
            continue;
        }

        // Scan forward for a matching >>>>>>> before treating this as a real
        // region -- everything in between is only ever ours/base/theirs
        // content, never the marker lines themselves, so none of it can ever
        // be echoed back out as a literal marker later.
        std::vector<std::string> ours;
        std::vector<std::string> base;
        std::vector<std::string> theirs;
        bool sawBase = false;
        bool sawSeparator = false;
        bool sawEnd = false;
        std::vector<std::string>* current = &ours;

        std::size_t j = i + 1;
        for (; j < lines.size(); ++j) {
            const std::string_view stripped = stripLineEnding(lines[j]);
            if (stripped.starts_with(">>>>>>>")) {
                sawEnd = true;
                break;
            }
            if (!sawSeparator && stripped.starts_with("|||||||")) {
                sawBase = true;
                current = &base;
                continue;
            }
            if (stripped == "=======") {
                sawSeparator = true;
                current = &theirs;
                continue;
            }
            current->push_back(lines[j]);
        }

        if (!sawEnd || !sawSeparator) {
            // Malformed: don't guess at a split. Keep the whole file as one
            // untouched text segment so the caller's whole-file take-left/
            // take-right path can still handle it.
            ParsedConflictFile fallback;
            fallback.wellFormed = false;
            ConflictSegment segment;
            segment.kind = ConflictSegmentKind::Text;
            segment.lines = lines;
            fallback.segments.push_back(std::move(segment));
            return fallback;
        }

        flushText();
        ConflictSegment region;
        region.kind = ConflictSegmentKind::Region;
        region.ours = std::move(ours);
        region.theirs = std::move(theirs);
        region.hasBase = sawBase;
        if (sawBase) {
            region.base = std::move(base);
        }
        result.segments.push_back(std::move(region));
        ++result.regionCount;
        i = j + 1;
    }
    flushText();
    return result;
}

std::optional<std::string> ConflictMarkerParser::assemble(
    const ParsedConflictFile& parsed, const std::vector<ConflictRegionResolution>& resolutions) {
    if (resolutions.size() != parsed.regionCount) {
        return std::nullopt;
    }
    for (const ConflictRegionResolution& resolution : resolutions) {
        if (resolution.choice == ConflictRegionChoice::Unresolved) {
            return std::nullopt;
        }
    }

    std::string output;
    std::size_t regionIndex = 0;
    for (const ConflictSegment& segment : parsed.segments) {
        if (segment.kind == ConflictSegmentKind::Text) {
            for (const std::string& line : segment.lines) {
                output += line;
            }
            continue;
        }

        const ConflictRegionResolution& resolution = resolutions[regionIndex++];
        const std::vector<std::string>* chosen = nullptr;
        switch (resolution.choice) {
            case ConflictRegionChoice::Ours:
                chosen = &segment.ours;
                break;
            case ConflictRegionChoice::Theirs:
                chosen = &segment.theirs;
                break;
            case ConflictRegionChoice::Custom:
                chosen = &resolution.customLines;
                break;
            case ConflictRegionChoice::Unresolved:
                break;  // Unreachable: rejected by the loop above.
        }
        for (const std::string& line : *chosen) {
            output += line;
        }
    }
    return output;
}

}  // namespace gbm
