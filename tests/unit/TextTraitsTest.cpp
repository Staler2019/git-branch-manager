// Design A5: two conflict sides coming from different branches can disagree
// on line ending and encoding, and combining them line-by-line is exactly
// the kind of difference that silently corrupts data -- mixed CRLF/LF, or a
// non-UTF-8 byte turned into mojibake, only shows up after the user has
// already committed. detectTextTraits() must run on the *raw bytes* before
// any decoding happens (see RepositorySession::requestConflictSides, which
// has ancestor/ours/theirs as plain std::string prior to any QString
// conversion) -- once decoded to QString, the original byte-level encoding
// is unrecoverable. This file covers only the pure detector; the app-side
// wiring that calls it lands in a separate commit (RepositorySession has no
// light test harness -- see ConflictUiTest.cpp's own note on this).
#include "core/git/TextTraits.h"

#include <gtest/gtest.h>

#include <string>

namespace gbm {
namespace {

TEST(TextTraits, PureLfIsDetectedAsLf) {
    const TextTraits traits = detectTextTraits("line1\nline2\nline3\n");
    EXPECT_EQ(traits.lineEnding, LineEndingKind::Lf);
    EXPECT_TRUE(traits.hasFinalNewline);
}

TEST(TextTraits, PureCrlfIsDetectedAsCrlf) {
    const TextTraits traits = detectTextTraits("line1\r\nline2\r\nline3\r\n");
    EXPECT_EQ(traits.lineEnding, LineEndingKind::Crlf);
    EXPECT_TRUE(traits.hasFinalNewline);
}

TEST(TextTraits, MixedLfAndCrlfIsDetectedAsMixed) {
    const TextTraits traits = detectTextTraits("line1\nline2\r\nline3\n");
    EXPECT_EQ(traits.lineEnding, LineEndingKind::Mixed);
}

// A CRLF pair contributes exactly one line ending, not one Crlf plus one
// stray Lf from the same \n -- a naive "\n" scan that doesn't look back for
// a preceding \r would double-count every CRLF line as Mixed.
TEST(TextTraits, CrlfLinesAreNotAlsoCountedAsBareLf) {
    const TextTraits traits = detectTextTraits("a\r\nb\r\nc\r\n");
    EXPECT_EQ(traits.lineEnding, LineEndingKind::Crlf);
}

// No newline at all -- a single line with no terminator. Not Mixed, not
// either kind: there is nothing to classify.
TEST(TextTraits, NoLineEndingsAtAllIsDetectedAsNone) {
    const TextTraits traits = detectTextTraits("just one line, no terminator");
    EXPECT_EQ(traits.lineEnding, LineEndingKind::None);
}

// A lone CR with no following LF (classic pre-OSX Mac Roman line ending) is
// deliberately not recognised as a line-ending kind of its own -- the plan
// only asks for LF/CRLF/Mixed. Pinned explicitly so the exclusion reads as
// a decision, not an oversight discovered by accident later.
TEST(TextTraits, LoneCarriageReturnIsNotCountedAsALineEnding) {
    const TextTraits traits = detectTextTraits("a\rb");
    EXPECT_EQ(traits.lineEnding, LineEndingKind::None);
}

TEST(TextTraits, EmptyContentHasFinalNewlineTrueAndNoLineEnding) {
    const TextTraits traits = detectTextTraits("");
    EXPECT_EQ(traits.lineEnding, LineEndingKind::None);
    EXPECT_TRUE(traits.hasFinalNewline);  // nothing is missing from nothing
}

TEST(TextTraits, MissingFinalNewlineIsDetected) {
    const TextTraits traits = detectTextTraits("line1\nline2");
    EXPECT_FALSE(traits.hasFinalNewline);
}

// Both traits are independent -- a CRLF file can still be missing its final
// newline, and the two must not interfere with each other's detection.
TEST(TextTraits, CrlfFileMissingFinalNewlineReportsBoth) {
    const TextTraits traits = detectTextTraits("line1\r\nline2\r\nline3");
    EXPECT_EQ(traits.lineEnding, LineEndingKind::Crlf);
    EXPECT_FALSE(traits.hasFinalNewline);
}

TEST(TextTraits, PlainAsciiIsDetectedAsUtf8) {
    const TextTraits traits = detectTextTraits("hello world\n");
    EXPECT_EQ(traits.encoding, EncodingKind::Utf8);
}

TEST(TextTraits, ValidMultibyteUtf8IsDetectedAsUtf8) {
    // "héllo wörld" -- é and ö each encode as a 2-byte UTF-8 sequence.
    const std::string content = "h\xC3\xA9llo w\xC3\xB6rld\n";
    const TextTraits traits = detectTextTraits(content);
    EXPECT_EQ(traits.encoding, EncodingKind::Utf8);
}

TEST(TextTraits, Utf8BomIsDetected) {
    const std::string content = "\xEF\xBB\xBFhello\n";
    const TextTraits traits = detectTextTraits(content);
    EXPECT_EQ(traits.encoding, EncodingKind::Utf8Bom);
}

TEST(TextTraits, Utf16LeBomIsDetected) {
    // "hi\n" in UTF-16LE: FF FE 68 00 69 00 0A 00 -- deliberately full of
    // 0x00 bytes, which a NUL-byte-first binary check would misclassify as
    // Binary. BOM detection must run before that check, not after.
    const std::string content{'\xFF', '\xFE', 'h', '\0', 'i', '\0', '\n', '\0'};
    const TextTraits traits = detectTextTraits(content);
    EXPECT_EQ(traits.encoding, EncodingKind::Utf16Le);
}

TEST(TextTraits, Utf16BeBomIsDetected) {
    const std::string content{'\xFE', '\xFF', '\0', 'h', '\0', 'i', '\0', '\n'};
    const TextTraits traits = detectTextTraits(content);
    EXPECT_EQ(traits.encoding, EncodingKind::Utf16Be);
}

// A byte sequence that is invalid UTF-8 (a bare continuation byte with no
// lead byte, and a lead byte promising more continuation bytes than follow)
// but contains no NUL and no recognised BOM -- some other 8-bit encoding
// (Big5, Latin-1, ...), not binary data.
TEST(TextTraits, InvalidUtf8ByteSequenceWithNoNulIsDetectedAsNonUtf8) {
    const std::string content{'a', '\xA0', 'b', '\n'};  // 0xA0: continuation byte, no lead
    const TextTraits traits = detectTextTraits(content);
    EXPECT_EQ(traits.encoding, EncodingKind::NonUtf8);
}

// Matches RepositorySession::requestWorkingTreeContent's existing gate
// exactly (raw->find('\0') == npos && isValidUtf8(*raw)) so Design A5's UI
// layer and that pre-existing editability check never disagree on what
// counts as safe: an embedded NUL is Binary, not merely NonUtf8.
TEST(TextTraits, EmbeddedNulByteIsDetectedAsBinary) {
    const std::string content{'a', '\0', 'b', '\n'};
    const TextTraits traits = detectTextTraits(content);
    EXPECT_EQ(traits.encoding, EncodingKind::Binary);
}

TEST(TextTraits, EmptyContentIsDetectedAsUtf8) {
    const TextTraits traits = detectTextTraits("");
    EXPECT_EQ(traits.encoding, EncodingKind::Utf8);
}

}  // namespace
}  // namespace gbm
