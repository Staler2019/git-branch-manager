#include "core/git/ConflictMarkerParser.h"

namespace gbm {

ParsedConflictFile ConflictMarkerParser::parse(std::string_view /*content*/) const {
    return {};
}

std::optional<std::string> ConflictMarkerParser::assemble(
    const ParsedConflictFile& /*parsed*/,
    const std::vector<ConflictRegionResolution>& /*resolutions*/) {
    return std::nullopt;
}

}  // namespace gbm
