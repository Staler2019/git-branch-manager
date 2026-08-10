// ConflictMarkerParser turns a working-tree file's raw conflict-marked
// content into plain-text and per-region segments, and reassembles a chosen
// resolution back into plain text that can never contain a literal marker
// line. A bug here shows up as either a corrupted resolved file or (worse) a
// conflict marker silently committed as if it were code, so the awkward
// cases -- diff3 base sections, markers that aren't really markers, missing
// trailing newlines, CRLF, malformed input -- get explicit coverage, same as
// UnifiedDiffParserTest.
#include "core/git/ConflictMarkerParser.h"

#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

TEST(ConflictMarkerParser, SplitsPlainTextAroundASingleRegion) {
    const std::string content =
        "before line 1\n"
        "<<<<<<< HEAD\n"
        "ours line 1\n"
        "ours line 2\n"
        "=======\n"
        "theirs line 1\n"
        ">>>>>>> feature\n"
        "after line 1\n";

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    EXPECT_TRUE(parsed.wellFormed);
    EXPECT_EQ(parsed.regionCount, 1u);
    ASSERT_EQ(parsed.segments.size(), 3u);

    EXPECT_EQ(parsed.segments[0].kind, ConflictSegmentKind::Text);
    EXPECT_EQ(parsed.segments[0].lines, std::vector<std::string>{"before line 1\n"});

    const ConflictSegment& region = parsed.segments[1];
    EXPECT_EQ(region.kind, ConflictSegmentKind::Region);
    EXPECT_FALSE(region.hasBase);
    EXPECT_TRUE(region.base.empty());
    EXPECT_EQ(region.ours, (std::vector<std::string>{"ours line 1\n", "ours line 2\n"}));
    EXPECT_EQ(region.theirs, std::vector<std::string>{"theirs line 1\n"});

    EXPECT_EQ(parsed.segments[2].kind, ConflictSegmentKind::Text);
    EXPECT_EQ(parsed.segments[2].lines, std::vector<std::string>{"after line 1\n"});
}

TEST(ConflictMarkerParser, HandlesMultipleRegionsInOneFile) {
    const std::string content =
        "<<<<<<< HEAD\n"
        "a-ours\n"
        "=======\n"
        "a-theirs\n"
        ">>>>>>> feature\n"
        "between\n"
        "<<<<<<< HEAD\n"
        "b-ours\n"
        "=======\n"
        "b-theirs\n"
        ">>>>>>> feature\n";

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    EXPECT_TRUE(parsed.wellFormed);
    EXPECT_EQ(parsed.regionCount, 2u);
    ASSERT_EQ(parsed.segments.size(), 3u);
    EXPECT_EQ(parsed.segments[0].kind, ConflictSegmentKind::Region);
    EXPECT_EQ(parsed.segments[0].ours, std::vector<std::string>{"a-ours\n"});
    EXPECT_EQ(parsed.segments[1].kind, ConflictSegmentKind::Text);
    EXPECT_EQ(parsed.segments[1].lines, std::vector<std::string>{"between\n"});
    EXPECT_EQ(parsed.segments[2].kind, ConflictSegmentKind::Region);
    EXPECT_EQ(parsed.segments[2].ours, std::vector<std::string>{"b-ours\n"});
}

TEST(ConflictMarkerParser, CapturesTheDiff3BaseSectionSeparatelyFromOurs) {
    const std::string content =
        "<<<<<<< HEAD\n"
        "ours\n"
        "||||||| merged common ancestors\n"
        "base\n"
        "=======\n"
        "theirs\n"
        ">>>>>>> feature\n";

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    ASSERT_EQ(parsed.segments.size(), 1u);
    const ConflictSegment& region = parsed.segments[0];
    EXPECT_TRUE(region.hasBase);
    EXPECT_EQ(region.base, std::vector<std::string>{"base\n"});
    // The base section must never be folded into ours -- that would silently
    // resolve every diff3 conflict to "keep the ancestor" instead of "keep
    // my side".
    EXPECT_EQ(region.ours, std::vector<std::string>{"ours\n"});
    EXPECT_EQ(region.theirs, std::vector<std::string>{"theirs\n"});
}

TEST(ConflictMarkerParser, PreservesAMissingTrailingNewlineAtEndOfFile) {
    const std::string content =
        "<<<<<<< HEAD\n"
        "ours\n"
        "=======\n"
        "theirs\n"
        ">>>>>>> feature\n"
        "after";  // no trailing '\n'

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    ASSERT_EQ(parsed.segments.size(), 2u);
    EXPECT_EQ(parsed.segments[1].lines, std::vector<std::string>{"after"});
}

TEST(ConflictMarkerParser, TreatsAnEqualsLineOutsideARegionAsPlainText) {
    // A Markdown-style underline that happens to be seven '=' characters
    // must not be mistaken for the middle of a conflict region it isn't
    // part of.
    const std::string content =
        "Title\n"
        "=======\n"
        "<<<<<<< HEAD\n"
        "ours\n"
        "=======\n"
        "theirs\n"
        ">>>>>>> feature\n";

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    ASSERT_EQ(parsed.segments.size(), 2u);
    EXPECT_EQ(parsed.segments[0].kind, ConflictSegmentKind::Text);
    EXPECT_EQ(parsed.segments[0].lines, (std::vector<std::string>{"Title\n", "=======\n"}));
    EXPECT_EQ(parsed.segments[1].kind, ConflictSegmentKind::Region);
    EXPECT_EQ(parsed.segments[1].ours, std::vector<std::string>{"ours\n"});
}

TEST(ConflictMarkerParser, ReturnsASingleTextSegmentWhenThereAreNoMarkers) {
    const std::string content = "just a normal file\nwith two lines\n";

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    EXPECT_TRUE(parsed.wellFormed);
    EXPECT_EQ(parsed.regionCount, 0u);
    ASSERT_EQ(parsed.segments.size(), 1u);
    EXPECT_EQ(parsed.segments[0].kind, ConflictSegmentKind::Text);
    EXPECT_EQ(parsed.segments[0].lines,
              (std::vector<std::string>{"just a normal file\n", "with two lines\n"}));
}

TEST(ConflictMarkerParser, HandlesAnEmptySideWithinARegion) {
    const std::string content =
        "<<<<<<< HEAD\n"
        "=======\n"
        "theirs only\n"
        ">>>>>>> feature\n";

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    ASSERT_EQ(parsed.segments.size(), 1u);
    EXPECT_TRUE(parsed.segments[0].ours.empty());
    EXPECT_EQ(parsed.segments[0].theirs, std::vector<std::string>{"theirs only\n"});
}

TEST(ConflictMarkerParser, TreatsAnUnterminatedMarkerAsPlainTextRatherThanCrashing) {
    const std::string content =
        "before\n"
        "<<<<<<< HEAD\n"
        "ours only, never closed\n";

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    EXPECT_FALSE(parsed.wellFormed);
    EXPECT_EQ(parsed.regionCount, 0u);
    ASSERT_EQ(parsed.segments.size(), 1u);
    EXPECT_EQ(parsed.segments[0].kind, ConflictSegmentKind::Text);
    // Nothing is dropped: the unmatched marker line itself survives verbatim.
    EXPECT_EQ(parsed.segments[0].lines,
              (std::vector<std::string>{
                  "before\n", "<<<<<<< HEAD\n", "ours only, never closed\n"}));
}

TEST(ConflictMarkerParser, AssemblesChosenSidesWithoutAnyMarkerText) {
    const std::string content =
        "before line 1\n"
        "<<<<<<< HEAD\n"
        "ours line 1\n"
        "ours line 2\n"
        "=======\n"
        "theirs line 1\n"
        ">>>>>>> feature\n"
        "after line 1\n";
    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    const auto ours = ConflictMarkerParser::assemble(
        parsed, {ConflictRegionResolution{ConflictRegionChoice::Ours, {}}});
    ASSERT_TRUE(ours.has_value());
    EXPECT_EQ(*ours, "before line 1\nours line 1\nours line 2\nafter line 1\n");
    EXPECT_EQ(ours->find("<<<<<<<"), std::string::npos);

    const auto theirs = ConflictMarkerParser::assemble(
        parsed, {ConflictRegionResolution{ConflictRegionChoice::Theirs, {}}});
    ASSERT_TRUE(theirs.has_value());
    EXPECT_EQ(*theirs, "before line 1\ntheirs line 1\nafter line 1\n");

    const auto custom = ConflictMarkerParser::assemble(
        parsed,
        {ConflictRegionResolution{ConflictRegionChoice::Custom, {"picked line\n"}}});
    ASSERT_TRUE(custom.has_value());
    EXPECT_EQ(*custom, "before line 1\npicked line\nafter line 1\n");
}

TEST(ConflictMarkerParser, AssembleNeverEmitsAMarkerLineAcrossMixedChoices) {
    const std::string content =
        "<<<<<<< HEAD\n"
        "a-ours\n"
        "=======\n"
        "a-theirs\n"
        ">>>>>>> feature\n"
        "between\n"
        "<<<<<<< HEAD\n"
        "b-ours\n"
        "=======\n"
        "b-theirs\n"
        ">>>>>>> feature\n";
    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);
    ASSERT_EQ(parsed.regionCount, 2u);

    const auto result = ConflictMarkerParser::assemble(
        parsed,
        {ConflictRegionResolution{ConflictRegionChoice::Ours, {}},
         ConflictRegionResolution{ConflictRegionChoice::Custom, {"chosen\n"}}});

    ASSERT_TRUE(result.has_value());
    EXPECT_EQ(*result, "a-ours\nbetween\nchosen\n");
    for (const char* marker : {"<<<<<<<", "=======", ">>>>>>>", "|||||||"}) {
        EXPECT_EQ(result->find(marker), std::string::npos) << "leaked marker: " << marker;
    }
}

TEST(ConflictMarkerParser, AssembleReturnsNulloptWhenAnyRegionIsUnresolved) {
    const std::string content =
        "<<<<<<< HEAD\n"
        "ours\n"
        "=======\n"
        "theirs\n"
        ">>>>>>> feature\n";
    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    EXPECT_FALSE(ConflictMarkerParser::assemble(
                     parsed, {ConflictRegionResolution{ConflictRegionChoice::Unresolved, {}}})
                     .has_value());
}

TEST(ConflictMarkerParser, AssembleReturnsNulloptWhenResolutionCountDoesNotMatchRegionCount) {
    const std::string content =
        "<<<<<<< HEAD\n"
        "ours\n"
        "=======\n"
        "theirs\n"
        ">>>>>>> feature\n";
    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);

    EXPECT_FALSE(ConflictMarkerParser::assemble(parsed, {}).has_value());
    EXPECT_FALSE(
        ConflictMarkerParser::assemble(
            parsed,
            {ConflictRegionResolution{ConflictRegionChoice::Ours, {}},
             ConflictRegionResolution{ConflictRegionChoice::Ours, {}}})
            .has_value());
}

TEST(ConflictMarkerParser, RoundtripsCrlfLineEndingsThroughParseAndAssemble) {
    const std::string content =
        "before\r\n"
        "<<<<<<< HEAD\r\n"
        "ours\r\n"
        "=======\r\n"
        "theirs\r\n"
        ">>>>>>> feature\r\n"
        "after\r\n";

    const ParsedConflictFile parsed = ConflictMarkerParser{}.parse(content);
    ASSERT_EQ(parsed.regionCount, 1u);

    const auto result = ConflictMarkerParser::assemble(
        parsed, {ConflictRegionResolution{ConflictRegionChoice::Ours, {}}});
    ASSERT_TRUE(result.has_value());
    EXPECT_EQ(*result, "before\r\nours\r\nafter\r\n");
}

}  // namespace
}  // namespace gbm
