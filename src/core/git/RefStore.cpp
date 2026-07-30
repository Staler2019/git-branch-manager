#include "core/git/RefStore.h"

#include "core/base/FsUtil.h"
#include "core/base/ThreadCheck.h"

#include <algorithm>
#include <charconv>
#include <utility>

namespace gbm {

namespace {

constexpr char kFieldSeparator = '\x1f';  // ASCII unit separator: cannot occur in a ref name.

RefKind kindForRef(std::string_view fullName) {
    if (fullName.rfind("refs/heads/", 0) == 0) return RefKind::LocalBranch;
    if (fullName.rfind("refs/remotes/", 0) == 0) return RefKind::RemoteBranch;
    if (fullName.rfind("refs/tags/", 0) == 0) return RefKind::Tag;
    if (fullName.rfind("refs/notes/", 0) == 0) return RefKind::Note;
    if (fullName == "refs/stash") return RefKind::Stash;
    return RefKind::Other;
}

std::string shortNameFor(std::string_view fullName, RefKind kind) {
    switch (kind) {
        case RefKind::LocalBranch:
            return std::string(fullName.substr(11));
        case RefKind::RemoteBranch:
            return std::string(fullName.substr(13));
        case RefKind::Tag:
            return std::string(fullName.substr(10));
        default:
            return std::string(fullName);
    }
}

/// Parses git's `%(upstream:track)` field, which looks like "[ahead 3, behind 1]",
/// "[ahead 2]", "[behind 5]", "[gone]" or is empty.
void parseTrack(std::string_view track, RefInfo& info) {
    if (track.empty()) {
        return;
    }
    info.hasTrackingInfo = true;

    auto readNumberAfter = [&track](std::string_view keyword) -> int {
        const std::size_t at = track.find(keyword);
        if (at == std::string_view::npos) {
            return 0;
        }
        std::string_view rest = track.substr(at + keyword.size());
        while (!rest.empty() && rest.front() == ' ') {
            rest.remove_prefix(1);
        }
        int value = 0;
        std::from_chars(rest.data(), rest.data() + rest.size(), value);
        return value;
    };

    info.ahead = readNumberAfter("ahead ");
    info.behind = readNumberAfter("behind ");
}

std::vector<std::string_view> splitFields(std::string_view line, char separator) {
    std::vector<std::string_view> fields;
    std::size_t start = 0;
    for (;;) {
        const std::size_t at = line.find(separator, start);
        if (at == std::string_view::npos) {
            fields.push_back(line.substr(start));
            return fields;
        }
        fields.push_back(line.substr(start, at - start));
        start = at + 1;
    }
}

}  // namespace

void RefSnapshot::buildIndex() {
    byTarget.clear();
    byTarget.reserve(refs.size() * 2);
    for (const RefInfo& ref : refs) {
        if (!ref.target.isNull()) {
            byTarget[ref.target].push_back(&ref);
        }
    }
}

const std::vector<const RefInfo*>* RefSnapshot::refsAt(const ObjectId& oid) const {
    const auto it = byTarget.find(oid);
    return it == byTarget.end() ? nullptr : &it->second;
}

std::vector<const RefInfo*> RefSnapshot::ofKind(RefKind kind) const {
    std::vector<const RefInfo*> result;
    for (const RefInfo& ref : refs) {
        if (ref.kind == kind) {
            result.push_back(&ref);
        }
    }
    return result;
}

RefStore::RefStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

bool RefStore::isValidBranchName(std::string_view name) {
    // Mirrors git-check-ref-format for the single-component case, so the user
    // gets a precise message before we spawn anything.
    if (name.empty() || name == "@") {
        return false;
    }
    if (name.front() == '.' || name.front() == '/' || name.front() == '-') {
        return false;
    }
    if (name.back() == '.' || name.back() == '/') {
        return false;
    }
    if (name.size() >= 5 && name.substr(name.size() - 5) == ".lock") {
        return false;
    }
    if (name.find("..") != std::string_view::npos || name.find("//") != std::string_view::npos ||
        name.find("@{") != std::string_view::npos) {
        return false;
    }
    for (char c : name) {
        const auto uc = static_cast<unsigned char>(c);
        if (uc < 0x20 || uc == 0x7F) {
            return false;
        }
        if (c == ' ' || c == '~' || c == '^' || c == ':' || c == '?' || c == '*' || c == '[' ||
            c == '\\') {
            return false;
        }
    }
    return true;
}

GitResult<HeadInfo> RefStore::readHead(CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    HeadInfo head;
    GitCommand command(paths_.commandDir(), {"symbolic-ref", "--quiet", "HEAD"});
    command.timeout = std::chrono::seconds(15);
    auto symbolic = runner_.run(command, token);

    if (symbolic && !symbolic->out.empty()) {
        head.kind = HeadInfo::Kind::Branch;
        head.fullRef = symbolic->out;
        head.branchName = shortNameFor(head.fullRef, RefKind::LocalBranch);
    } else {
        head.kind = HeadInfo::Kind::Detached;
    }

    GitCommand revParse(paths_.commandDir(), {"rev-parse", "--verify", "--quiet", "HEAD"});
    revParse.timeout = std::chrono::seconds(15);
    auto resolved = runner_.run(revParse, token);
    if (!resolved || resolved->out.empty()) {
        // No commits yet. A fresh repository must still open cleanly rather than
        // reporting an error, so this is a normal state, not a failure.
        head.kind = HeadInfo::Kind::Unborn;
        return head;
    }
    head.target = ObjectId::fromHex(resolved->out);
    return head;
}

GitResult<RefSnapshotPtr> RefStore::load(CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    auto snapshot = std::make_shared<RefSnapshot>();

    auto head = readHead(token);
    if (!head) {
        return fail(std::move(head).error());
    }
    snapshot->head = *head;

    // One invocation for every ref, including tracking info. %(objectname) is
    // the ref's own target; %(*objectname) is the peeled commit for annotated
    // tags, which is what the graph needs to place them.
    std::string format;
    format += "%(refname)";
    format += kFieldSeparator;
    format += "%(objecttype)";
    format += kFieldSeparator;
    format += "%(objectname)";
    format += kFieldSeparator;
    format += "%(*objectname)";
    format += kFieldSeparator;
    format += "%(upstream)";
    format += kFieldSeparator;
    format += "%(upstream:track)";
    format += kFieldSeparator;
    format += "%(HEAD)";
    format += kFieldSeparator;
    format += "%(worktreepath)";

    GitCommand command(paths_.commandDir(), {"for-each-ref", "--format=" + format});
    command.timeout = std::chrono::seconds(120);

    std::vector<RefInfo> refs;
    const LineSink sink = [&refs](std::string_view line) {
        if (line.empty()) {
            return true;
        }
        const auto fields = splitFields(line, kFieldSeparator);
        if (fields.size() < 7) {
            return true;  // Unexpected shape: skip the ref rather than abort the load.
        }

        RefInfo info;
        info.fullName = std::string(fields[0]);
        info.kind = kindForRef(info.fullName);
        info.shortName = shortNameFor(info.fullName, info.kind);

        const std::string_view objectType = fields[1];
        const std::string_view objectName = fields[2];
        const std::string_view peeled = fields[3];

        if (objectType == "tag" && !peeled.empty()) {
            info.tagObject = ObjectId::fromHex(objectName);
            info.target = ObjectId::fromHex(peeled);
        } else {
            info.target = ObjectId::fromHex(objectName);
        }

        info.upstream = std::string(fields[4]);
        parseTrack(fields[5], info);
        info.isHead = fields[6] == "*";
        if (fields.size() > 7) {
            info.worktreePath = std::string(fields[7]);
        }

        refs.push_back(std::move(info));
        return true;
    };

    auto result =
        runner_.streamSeparated(command, IProcessRunner::Separator::Newline, sink, nullptr, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    snapshot->totalRefCount = refs.size();
    snapshot->refCountGuardTripped = refs.size() > kRefCountGuard;
    snapshot->refs = std::move(refs);

    // Stable, human-friendly ordering: local branches, remotes, tags, then the
    // rest, alphabetically within each group.
    std::sort(snapshot->refs.begin(), snapshot->refs.end(), [](const RefInfo& a, const RefInfo& b) {
        if (a.kind != b.kind) {
            return static_cast<int>(a.kind) < static_cast<int>(b.kind);
        }
        return a.shortName < b.shortName;
    });

    snapshot->buildIndex();
    return RefSnapshotPtr(snapshot);
}

std::vector<std::string> RefStore::historySeedRefs(const RefSnapshot& refs) {
    // Order matters: the graph builder gives lane 0 to the first tip it sees, so
    // HEAD and the trunk must come before --all. Everything after that is just
    // completeness.
    std::vector<std::string> seeds;
    auto push = [&seeds](const std::string& value) {
        if (value.empty()) {
            return;
        }
        if (std::find(seeds.begin(), seeds.end(), value) == seeds.end()) {
            seeds.push_back(value);
        }
    };

    if (refs.head.kind == HeadInfo::Kind::Branch && !refs.head.fullRef.empty()) {
        push(refs.head.fullRef);
    } else if (refs.head.kind == HeadInfo::Kind::Detached) {
        push("HEAD");
    }

    // The upstream of HEAD, so the graph shows what the remote has too.
    for (const RefInfo& ref : refs.refs) {
        if (ref.isHead && !ref.upstream.empty()) {
            push(ref.upstream);
        }
    }

    // Conventional trunk names, whichever exists.
    for (const char* trunk :
         {"refs/heads/main", "refs/heads/master", "refs/heads/develop", "refs/heads/trunk"}) {
        const bool exists =
            std::any_of(refs.refs.begin(), refs.refs.end(), [trunk](const RefInfo& ref) {
                return ref.fullName == trunk;
            });
        if (exists) {
            push(trunk);
        }
    }

    return seeds;
}

}  // namespace gbm
