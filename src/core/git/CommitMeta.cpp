#include "core/git/CommitMeta.h"

#include <charconv>
#include <cstdlib>

namespace gbm {

namespace {

std::int64_t parseInt(std::string_view text) {
    std::int64_t value = 0;
    const auto* begin = text.data();
    const auto* end = text.data() + text.size();
    const auto result = std::from_chars(begin, end, value);
    return result.ec == std::errc{} ? value : 0;
}

// An explicit scan instead of std::string_view::find(char, from): the latter
// lowers to char_traits::find -> __builtin_memchr, which GCC 11 at -O2 can
// misjudge the bound of after inlining through a substr/min chain, emitting
// a false-positive -Wstringop-overread (the memchr call itself is correct).
//
// Applied unconditionally for every compiler, not just GCC 11 -- a version
// guard (e.g. #if __GNUC__ == 11) would mean GCC 12+ silently falls back to
// the vectorized find() path that nobody has re-verified is free of this
// false positive, for a signature line that is at most a few dozen bytes
// long. Given the project's -Wstringop-overread policy (a real memory-safety
// warning gets fixed at the root, not suppressed -- see CONTRIBUTING.md), one
// verified code path on every compiler beats a faster, unverified one on
// most of them.
std::size_t findChar(std::string_view text, char needle, std::size_t from = 0) {
    for (std::size_t i = from; i < text.size(); ++i) {
        if (text[i] == needle) {
            return i;
        }
    }
    return std::string_view::npos;
}

}  // namespace

Signature parseSignature(std::string_view text) {
    // Format: "Name Surname <email@example.com> 1699999999 +0200".
    // Names legitimately contain '<', so scan from the right for the email
    // delimiters rather than the left.
    Signature signature;
    const std::size_t emailEnd = text.rfind('>');
    const std::size_t emailStart =
        emailEnd == std::string_view::npos ? std::string_view::npos : text.rfind('<', emailEnd);

    if (emailStart == std::string_view::npos || emailEnd == std::string_view::npos) {
        signature.name = std::string(text);
        return signature;
    }

    std::string_view name = text.substr(0, emailStart);
    while (!name.empty() && name.back() == ' ') {
        name.remove_suffix(1);
    }
    signature.name = std::string(name);
    signature.email = std::string(text.substr(emailStart + 1, emailEnd - emailStart - 1));

    std::string_view rest = text.substr(emailEnd + 1);
    while (!rest.empty() && rest.front() == ' ') {
        rest.remove_prefix(1);
    }
    if (rest.empty()) {
        return signature;
    }

    const std::size_t space = findChar(rest, ' ');
    signature.when = parseInt(space == std::string_view::npos ? rest : rest.substr(0, space));

    if (space != std::string_view::npos) {
        std::string_view zone = rest.substr(space + 1);
        if (zone.size() >= 5) {
            const int sign = zone[0] == '-' ? -1 : 1;
            const int hours = static_cast<int>(parseInt(zone.substr(1, 2)));
            const int minutes = static_cast<int>(parseInt(zone.substr(3, 2)));
            signature.tzOffsetMinutes = sign * (hours * 60 + minutes);
        }
    }
    return signature;
}

CommitMeta CommitMeta::parseRawCommit(const ObjectId& oid, std::string_view raw) {
    CommitMeta meta;
    meta.oid = oid;

    std::size_t cursor = 0;
    // Headers run until the first blank line. Anything unrecognised (gpgsig,
    // mergetag, encoding, and whatever git adds next) is skipped rather than
    // treated as an error, so an unfamiliar header never breaks history browsing.
    while (cursor < raw.size()) {
        const std::size_t lineEnd = findChar(raw, '\n', cursor);
        const std::string_view line = raw.substr(
            cursor, lineEnd == std::string_view::npos ? std::string_view::npos : lineEnd - cursor);
        if (line.empty()) {
            cursor = lineEnd == std::string_view::npos ? raw.size() : lineEnd + 1;
            break;
        }

        if (line.rfind("tree ", 0) == 0) {
            meta.tree = ObjectId::fromHex(line.substr(5));
        } else if (line.rfind("parent ", 0) == 0) {
            ObjectId parent = ObjectId::fromHex(line.substr(7));
            if (!parent.isNull()) {
                meta.parents.push_back(parent);
            }
        } else if (line.rfind("author ", 0) == 0) {
            meta.author = parseSignature(line.substr(7));
        } else if (line.rfind("committer ", 0) == 0) {
            meta.committer = parseSignature(line.substr(10));
        } else if (line.rfind("gpgsig", 0) == 0) {
            meta.signedCommit = true;
        }

        if (lineEnd == std::string_view::npos) {
            cursor = raw.size();
            break;
        }
        cursor = lineEnd + 1;

        // Continuation lines of a multi-line header (gpgsig) start with a space.
        while (cursor < raw.size() && raw[cursor] == ' ') {
            const std::size_t continuationEnd = findChar(raw, '\n', cursor);
            if (continuationEnd == std::string_view::npos) {
                cursor = raw.size();
                break;
            }
            cursor = continuationEnd + 1;
        }
    }

    std::string_view message = raw.substr(std::min(cursor, raw.size()));
    const std::size_t subjectEnd = findChar(message, '\n');
    if (subjectEnd == std::string_view::npos) {
        meta.subject = std::string(message);
        return meta;
    }

    meta.subject = std::string(message.substr(0, subjectEnd));
    std::string_view body = message.substr(subjectEnd + 1);
    while (!body.empty() && (body.front() == '\n' || body.front() == '\r')) {
        body.remove_prefix(1);
    }
    while (!body.empty() && (body.back() == '\n' || body.back() == '\r')) {
        body.remove_suffix(1);
    }
    meta.body = std::string(body);
    return meta;
}

}  // namespace gbm
