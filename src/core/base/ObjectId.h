#pragma once

#include <array>
#include <cstdint>
#include <cstring>
#include <functional>
#include <string>
#include <string_view>

namespace gbm {

/// A packed git object id. Stored as raw bytes rather than hex because at 500k
/// commits the difference is 10 MB vs 20 MB of resident memory, and because
/// comparison and hashing get to work on machine words.
///
/// Sized for SHA-256 (32 bytes) with an explicit length so SHA-1 repositories
/// only compare the 20 bytes that matter.
class ObjectId {
public:
    static constexpr std::size_t kMaxBytes = 32;
    static constexpr std::size_t kSha1Bytes = 20;

    ObjectId() = default;

    /// Parses 40 (SHA-1) or 64 (SHA-256) hex characters. Returns false and
    /// leaves the object null on anything else, including short prefixes.
    bool parseHex(std::string_view hex) {
        if (hex.size() != 40 && hex.size() != 64) {
            return false;
        }
        const std::size_t bytes = hex.size() / 2;
        std::array<std::uint8_t, kMaxBytes> parsed{};
        for (std::size_t i = 0; i < bytes; ++i) {
            const int hi = hexValue(hex[2 * i]);
            const int lo = hexValue(hex[2 * i + 1]);
            if (hi < 0 || lo < 0) {
                return false;
            }
            parsed[i] = static_cast<std::uint8_t>((hi << 4) | lo);
        }
        bytes_ = parsed;
        length_ = static_cast<std::uint8_t>(bytes);
        return true;
    }

    static ObjectId fromHex(std::string_view hex) {
        ObjectId id;
        id.parseHex(hex);
        return id;
    }

    bool isNull() const noexcept { return length_ == 0; }

    std::size_t byteLength() const noexcept { return length_; }

    const std::uint8_t* bytes() const noexcept { return bytes_.data(); }

    std::string hex() const {
        static constexpr char kDigits[] = "0123456789abcdef";
        std::string out;
        out.resize(static_cast<std::size_t>(length_) * 2);
        for (std::size_t i = 0; i < length_; ++i) {
            out[2 * i] = kDigits[bytes_[i] >> 4];
            out[2 * i + 1] = kDigits[bytes_[i] & 0x0F];
        }
        return out;
    }

    /// Abbreviated form for display. Never used as a lookup key.
    std::string shortHex(std::size_t chars = 8) const {
        std::string full = hex();
        return full.size() <= chars ? full : full.substr(0, chars);
    }

    friend bool operator==(const ObjectId& a, const ObjectId& b) noexcept {
        return a.length_ == b.length_ &&
               std::memcmp(a.bytes_.data(), b.bytes_.data(), a.length_) == 0;
    }

    friend bool operator!=(const ObjectId& a, const ObjectId& b) noexcept { return !(a == b); }

    friend bool operator<(const ObjectId& a, const ObjectId& b) noexcept {
        if (a.length_ != b.length_) {
            return a.length_ < b.length_;
        }
        return std::memcmp(a.bytes_.data(), b.bytes_.data(), a.length_) < 0;
    }

    /// FNV-1a over the significant bytes. Also the source of graph lane colours,
    /// so it must stay stable across releases: a change would reshuffle every
    /// branch colour and invalidate the golden tests.
    std::uint64_t hash() const noexcept {
        std::uint64_t h = 0xcbf29ce484222325ULL;
        for (std::size_t i = 0; i < length_; ++i) {
            h ^= bytes_[i];
            h *= 0x100000001b3ULL;
        }
        return h;
    }

private:
    static int hexValue(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    }

    std::array<std::uint8_t, kMaxBytes> bytes_{};
    std::uint8_t length_ = 0;
};

// Pinned like RowMeta and Edge in GraphSnapshot.h: this is the largest
// per-row field in GraphSnapshot::oids, so a silent size change would move
// the memory budget without any of those static_asserts catching it.
static_assert(sizeof(ObjectId) == 33, "ObjectId must stay 33 bytes; see the memory budget");

}  // namespace gbm

template <>
struct std::hash<gbm::ObjectId> {
    std::size_t operator()(const gbm::ObjectId& id) const noexcept {
        return static_cast<std::size_t>(id.hash());
    }
};
