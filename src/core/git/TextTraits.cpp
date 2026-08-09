#include "core/git/TextTraits.h"

namespace gbm {

namespace {

LineEndingKind detectLineEnding(std::string_view rawBytes) {
    bool sawLf = false;
    bool sawCrlf = false;
    for (std::size_t i = 0; i < rawBytes.size(); ++i) {
        if (rawBytes[i] != '\n') {
            continue;
        }
        // A CRLF pair is one line ending, not a Crlf plus a separately
        // counted bare Lf from the same '\n' -- look back for the '\r'
        // before deciding which bucket this terminator belongs to.
        if (i > 0 && rawBytes[i - 1] == '\r') {
            sawCrlf = true;
        } else {
            sawLf = true;
        }
    }
    if (sawLf && sawCrlf) {
        return LineEndingKind::Mixed;
    }
    if (sawCrlf) {
        return LineEndingKind::Crlf;
    }
    if (sawLf) {
        return LineEndingKind::Lf;
    }
    return LineEndingKind::None;
}

// Mirrors RepositorySession.cpp's isValidUtf8 exactly (same permissive
// algorithm: no overlong-encoding or surrogate-range rejection) -- core
// cannot include from src/app/bridge, so this is a deliberate duplicate
// rather than a shared helper. Keeping the same leniency means this
// detector's Utf8/NonUtf8 split never disagrees with the app's own
// pre-existing editability gate.
bool isValidUtf8(std::string_view text) {
    std::size_t i = 0;
    const std::size_t n = text.size();
    while (i < n) {
        const auto byte = static_cast<unsigned char>(text[i]);
        std::size_t extra = 0;
        if (byte <= 0x7F) {
            extra = 0;
        } else if ((byte & 0xE0) == 0xC0) {
            extra = 1;
        } else if ((byte & 0xF0) == 0xE0) {
            extra = 2;
        } else if ((byte & 0xF8) == 0xF0) {
            extra = 3;
        } else {
            return false;
        }
        if (i + extra >= n) {
            return false;
        }
        for (std::size_t k = 1; k <= extra; ++k) {
            if ((static_cast<unsigned char>(text[i + k]) & 0xC0) != 0x80) {
                return false;
            }
        }
        i += extra + 1;
    }
    return true;
}

bool startsWith(std::string_view rawBytes, std::string_view prefix) {
    return rawBytes.size() >= prefix.size() && rawBytes.substr(0, prefix.size()) == prefix;
}

EncodingKind detectEncoding(std::string_view rawBytes) {
    // BOM checks first, before the NUL-byte binary check below: a UTF-16
    // payload is full of 0x00 bytes by construction (every ASCII code point
    // has a null high or low byte), so checking for NUL first would
    // misclassify every UTF-16 file as Binary before its BOM is ever looked
    // at.
    if (startsWith(rawBytes, "\xEF\xBB\xBF")) {
        return EncodingKind::Utf8Bom;
    }
    if (startsWith(rawBytes, "\xFF\xFE")) {
        return EncodingKind::Utf16Le;
    }
    if (startsWith(rawBytes, "\xFE\xFF")) {
        return EncodingKind::Utf16Be;
    }
    // Matches RepositorySession::requestWorkingTreeContent's existing gate
    // (raw->find('\0') == npos && isValidUtf8(*raw)) exactly, so Design A5's
    // UI layer never disagrees with that pre-existing editability check on
    // what counts as safe to edit line-by-line.
    if (rawBytes.find('\0') != std::string_view::npos) {
        return EncodingKind::Binary;
    }
    return isValidUtf8(rawBytes) ? EncodingKind::Utf8 : EncodingKind::NonUtf8;
}

}  // namespace

TextTraits detectTextTraits(std::string_view rawBytes) {
    TextTraits traits;
    traits.lineEnding = detectLineEnding(rawBytes);
    traits.encoding = detectEncoding(rawBytes);
    traits.hasFinalNewline = rawBytes.empty() || rawBytes.back() == '\n';
    return traits;
}

}  // namespace gbm
