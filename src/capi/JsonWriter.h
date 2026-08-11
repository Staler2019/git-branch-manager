#pragma once

// A tiny hand-rolled JSON writer. The capi layer's JSON surface is entirely
// this library's own output (nothing round-trips through JSON *parsing* on
// the C++ side in M0 -- inbound calls take scalar C parameters instead, see
// gbm_capi.h), so a minimal escaping writer is enough and avoids taking on a
// JSON dependency for one direction of a boundary that mostly carries
// primitives.

#include <cstdint>
#include <string>
#include <string_view>

namespace gbm::capi {

inline void jsonAppendEscaped(std::string& out, std::string_view value) {
    out.push_back('"');
    for (const char c : value) {
        switch (c) {
            case '"':
                out += "\\\"";
                break;
            case '\\':
                out += "\\\\";
                break;
            case '\n':
                out += "\\n";
                break;
            case '\r':
                out += "\\r";
                break;
            case '\t':
                out += "\\t";
                break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    static constexpr char kHex[] = "0123456789abcdef";
                    out += "\\u00";
                    out.push_back(kHex[(c >> 4) & 0xF]);
                    out.push_back(kHex[c & 0xF]);
                } else {
                    out.push_back(c);
                }
        }
    }
    out.push_back('"');
}

inline std::string jsonEscaped(std::string_view value) {
    std::string out;
    jsonAppendEscaped(out, value);
    return out;
}

inline void jsonAppendBool(std::string& out, bool value) {
    out += value ? "true" : "false";
}

inline void jsonAppendInt(std::string& out, std::int64_t value) {
    out += std::to_string(value);
}

}  // namespace gbm::capi
