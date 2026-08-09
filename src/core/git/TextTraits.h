#pragma once

#include <string_view>

namespace gbm {

/// Which line-ending convention a file's content uses. `Mixed` means both
/// LF-only and CRLF line endings appear in the same content -- combining
/// two conflict sides line-by-line when their line endings disagree is
/// exactly the kind of silent data corruption Design A5 exists to flag.
///
/// A lone '\r' not followed by '\n' (the classic pre-OSX Mac Roman
/// convention) is deliberately not recognised as a line ending of its own --
/// only LF/CRLF/Mixed are in scope here. Content containing only lone CRs
/// (or no line terminators at all) detects as `None`.
enum class LineEndingKind { None, Lf, Crlf, Mixed };

/// Which encoding a file's content appears to use, cheapest and most
/// specific signal first: a byte-order mark identifies UTF-16 or a UTF-8
/// BOM outright; absent that, an embedded NUL byte is treated the same way
/// RepositorySession::requestWorkingTreeContent already treats one -- as
/// binary, not text -- and only then is the content checked for well-formed
/// UTF-8.
enum class EncodingKind { Utf8, Utf8Bom, Utf16Le, Utf16Be, NonUtf8, Binary };

struct TextTraits {
    LineEndingKind lineEnding = LineEndingKind::None;
    EncodingKind encoding = EncodingKind::Utf8;
    /// False when the last line has no trailing newline of its own. Vacuously
    /// true for empty content -- there is no last line to be missing one.
    bool hasFinalNewline = true;
};

/// Detects `rawBytes`' line-ending and encoding traits. Must run on
/// undecoded bytes -- once content has already been converted to a QString
/// (or any other Unicode-only representation), the original byte-level
/// encoding is no longer recoverable. See RepositorySession::
/// requestConflictSides, where ancestor/ours/theirs are still plain
/// std::string prior to any QString conversion, which is where this is
/// meant to be called from.
TextTraits detectTextTraits(std::string_view rawBytes);

}  // namespace gbm
