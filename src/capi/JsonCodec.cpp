#include "capi/JsonCodec.h"

#include "capi/JsonWriter.h"

namespace gbm::capi {

std::string toJson(const GitError& error) {
    std::string out = "{";
    out += "\"code\":";
    jsonAppendInt(out, static_cast<std::int64_t>(error.code));
    out += ",\"codeName\":";
    jsonAppendEscaped(out, toString(error.code));
    out += ",\"message\":";
    jsonAppendEscaped(out, error.message);
    out += ",\"detail\":";
    jsonAppendEscaped(out, error.detail);
    out += ",\"argv\":[";
    for (std::size_t i = 0; i < error.argv.size(); ++i) {
        if (i != 0) out += ',';
        jsonAppendEscaped(out, error.argv[i]);
    }
    out += "],\"exitCode\":";
    jsonAppendInt(out, error.exitCode);
    out += '}';
    return out;
}

std::string toJson(const RepoState& state) {
    std::string out = "{";
    out += "\"flags\":";
    jsonAppendInt(out, state.flags);
    out += ",\"isClean\":";
    jsonAppendBool(out, state.isClean());
    out += ",\"isSequencerOperation\":";
    jsonAppendBool(out, state.isSequencerOperation());
    out += ",\"rebaseStep\":";
    jsonAppendInt(out, state.rebaseStep);
    out += ",\"rebaseTotal\":";
    jsonAppendInt(out, state.rebaseTotal);
    out += ",\"rebaseOntoLabel\":";
    jsonAppendEscaped(out, state.rebaseOntoLabel);
    out += ",\"indexLocked\":";
    jsonAppendBool(out, state.indexLocked);
    out += ",\"indexLockAgeSeconds\":";
    if (state.indexLockAgeSeconds.has_value()) {
        jsonAppendInt(out, *state.indexLockAgeSeconds);
    } else {
        out += "null";
    }
    out += ",\"describe\":";
    jsonAppendEscaped(out, state.describe());
    out += '}';
    return out;
}

namespace {

std::string signatureJson(const Signature& sig) {
    std::string out = "{";
    out += "\"name\":";
    jsonAppendEscaped(out, sig.name);
    out += ",\"email\":";
    jsonAppendEscaped(out, sig.email);
    out += ",\"when\":";
    jsonAppendInt(out, sig.when);
    out += ",\"tzOffsetMinutes\":";
    jsonAppendInt(out, sig.tzOffsetMinutes);
    out += '}';
    return out;
}

}  // namespace

std::string toJson(const CommitMeta& meta) {
    std::string out = "{";
    out += "\"oid\":";
    jsonAppendEscaped(out, meta.oid.hex());
    out += ",\"tree\":";
    jsonAppendEscaped(out, meta.tree.hex());
    out += ",\"parents\":[";
    for (std::size_t i = 0; i < meta.parents.size(); ++i) {
        if (i != 0) out += ',';
        jsonAppendEscaped(out, meta.parents[i].hex());
    }
    out += "],\"author\":";
    out += signatureJson(meta.author);
    out += ",\"committer\":";
    out += signatureJson(meta.committer);
    out += ",\"subject\":";
    jsonAppendEscaped(out, meta.subject);
    out += ",\"body\":";
    jsonAppendEscaped(out, meta.body);
    out += ",\"signed\":";
    jsonAppendBool(out, meta.signedCommit);
    out += '}';
    return out;
}

namespace {

std::string operationChoiceJson(const OperationChoice& choice) {
    std::string out = "{";
    out += "\"kind\":";
    jsonAppendInt(out, static_cast<std::int64_t>(choice.kind));
    out += ",\"label\":";
    jsonAppendEscaped(out, choice.label);
    out += ",\"explanation\":";
    jsonAppendEscaped(out, choice.explanation);
    out += ",\"destructive\":";
    jsonAppendBool(out, choice.destructive);
    out += '}';
    return out;
}

}  // namespace

std::string toJson(const OperationOutcome& outcome) {
    std::string out = "{";
    out += "\"succeeded\":";
    jsonAppendBool(out, outcome.succeeded);
    out += ",\"error\":";
    if (outcome.error.has_value()) {
        out += toJson(*outcome.error);
    } else {
        out += "null";
    }
    out += ",\"choices\":[";
    for (std::size_t i = 0; i < outcome.choices.size(); ++i) {
        if (i != 0) out += ',';
        out += operationChoiceJson(outcome.choices[i]);
    }
    out += "],\"summary\":";
    jsonAppendEscaped(out, outcome.summary);
    out += '}';
    return out;
}

std::string toJson(const RepoRecord& record) {
    std::string out = "{";
    out += "\"id\":";
    jsonAppendInt(out, record.id);
    out += ",\"baseFolderId\":";
    jsonAppendInt(out, record.baseFolderId);
    out += ",\"workDir\":";
    jsonAppendEscaped(out, record.workDir);
    out += ",\"gitDir\":";
    jsonAppendEscaped(out, record.gitDir);
    out += ",\"commonDir\":";
    jsonAppendEscaped(out, record.commonDir);
    out += ",\"kind\":";
    jsonAppendInt(out, static_cast<std::int64_t>(record.kind));
    out += ",\"name\":";
    jsonAppendEscaped(out, record.name);
    out += ",\"parentRepoId\":";
    if (record.parentRepoId.has_value()) {
        jsonAppendInt(out, *record.parentRepoId);
    } else {
        out += "null";
    }
    out += ",\"depth\":";
    jsonAppendInt(out, record.depth);
    out += ",\"discoveredAt\":";
    jsonAppendInt(out, record.discoveredAt);
    out += ",\"missingSince\":";
    if (record.missingSince.has_value()) {
        jsonAppendInt(out, *record.missingSince);
    } else {
        out += "null";
    }
    out += '}';
    return out;
}

namespace {

std::string refInfoJson(const RefInfo& ref) {
    std::string out = "{";
    out += "\"fullName\":";
    jsonAppendEscaped(out, ref.fullName);
    out += ",\"shortName\":";
    jsonAppendEscaped(out, ref.shortName);
    out += ",\"kind\":";
    jsonAppendInt(out, static_cast<std::int64_t>(ref.kind));
    out += ",\"target\":";
    jsonAppendEscaped(out, ref.target.hex());
    out += ",\"upstream\":";
    jsonAppendEscaped(out, ref.upstream);
    out += ",\"ahead\":";
    jsonAppendInt(out, ref.ahead);
    out += ",\"behind\":";
    jsonAppendInt(out, ref.behind);
    out += ",\"hasTrackingInfo\":";
    jsonAppendBool(out, ref.hasTrackingInfo);
    out += ",\"isGone\":";
    jsonAppendBool(out, ref.isGone);
    out += ",\"isHead\":";
    jsonAppendBool(out, ref.isHead);
    out += ",\"isSymbolic\":";
    jsonAppendBool(out, ref.isSymbolic);
    out += ",\"worktreePath\":";
    jsonAppendEscaped(out, ref.worktreePath);
    out += '}';
    return out;
}

std::string headInfoJson(const HeadInfo& head) {
    std::string out = "{";
    out += "\"kind\":";
    jsonAppendInt(out, static_cast<std::int64_t>(head.kind));
    out += ",\"branchName\":";
    jsonAppendEscaped(out, head.branchName);
    out += ",\"fullRef\":";
    jsonAppendEscaped(out, head.fullRef);
    out += ",\"target\":";
    jsonAppendEscaped(out, head.target.hex());
    out += '}';
    return out;
}

}  // namespace

std::string toJson(const RefSnapshot& refs) {
    std::string out = "{";
    out += "\"head\":";
    out += headInfoJson(refs.head);
    out += ",\"refCountGuardTripped\":";
    jsonAppendBool(out, refs.refCountGuardTripped);
    out += ",\"totalRefCount\":";
    jsonAppendInt(out, static_cast<std::int64_t>(refs.totalRefCount));
    out += ",\"refs\":[";
    for (std::size_t i = 0; i < refs.refs.size(); ++i) {
        if (i != 0) out += ',';
        out += refInfoJson(refs.refs[i]);
    }
    out += "]}";
    return out;
}

std::string toJson(const std::vector<RepoRecord>& records) {
    std::string out = "[";
    for (std::size_t i = 0; i < records.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(records[i]);
    }
    out += ']';
    return out;
}

namespace {

std::string workingCopyEntryJson(const WorkingCopyEntry& entry) {
    std::string out = "{";
    out += "\"path\":";
    jsonAppendEscaped(out, entry.path);
    out += ",\"oldPath\":";
    jsonAppendEscaped(out, entry.oldPath);
    out += ",\"untracked\":";
    jsonAppendBool(out, entry.untracked);
    out += ",\"staged\":";
    jsonAppendBool(out, entry.staged);
    out += ",\"indexStatus\":";
    jsonAppendInt(out, static_cast<std::int64_t>(entry.indexStatus));
    out += ",\"hasUnstagedChange\":";
    jsonAppendBool(out, entry.hasUnstagedChange);
    out += ",\"worktreeStatus\":";
    jsonAppendInt(out, static_cast<std::int64_t>(entry.worktreeStatus));
    out += ",\"conflict\":";
    jsonAppendInt(out, static_cast<std::int64_t>(entry.conflict));
    out += ",\"ancestorBlob\":";
    jsonAppendEscaped(out, entry.ancestorBlob);
    out += ",\"oursBlob\":";
    jsonAppendEscaped(out, entry.oursBlob);
    out += ",\"theirsBlob\":";
    jsonAppendEscaped(out, entry.theirsBlob);
    out += ",\"similarity\":";
    jsonAppendInt(out, entry.similarity);
    out += ",\"isSubmodule\":";
    jsonAppendBool(out, entry.isSubmodule);
    out += ",\"isConflicted\":";
    jsonAppendBool(out, entry.isConflicted());
    out += '}';
    return out;
}

}  // namespace

std::string toJson(const WorkingCopyStatus& status) {
    std::string out = "{\"entries\":[";
    for (std::size_t i = 0; i < status.entries.size(); ++i) {
        if (i != 0) out += ',';
        out += workingCopyEntryJson(status.entries[i]);
    }
    out += "]}";
    return out;
}

namespace {

std::string diffLineJson(const DiffLine& line) {
    std::string out = "{";
    out += "\"kind\":";
    jsonAppendInt(out, static_cast<std::int64_t>(line.kind));
    out += ",\"oldLine\":";
    jsonAppendInt(out, line.oldLine);
    out += ",\"newLine\":";
    jsonAppendInt(out, line.newLine);
    out += ",\"text\":";
    jsonAppendEscaped(out, line.text);
    out += '}';
    return out;
}

std::string diffHunkJson(const DiffHunk& hunk) {
    std::string out = "{";
    out += "\"oldStart\":";
    jsonAppendInt(out, hunk.oldStart);
    out += ",\"oldCount\":";
    jsonAppendInt(out, hunk.oldCount);
    out += ",\"newStart\":";
    jsonAppendInt(out, hunk.newStart);
    out += ",\"newCount\":";
    jsonAppendInt(out, hunk.newCount);
    out += ",\"heading\":";
    jsonAppendEscaped(out, hunk.heading);
    out += ",\"lines\":[";
    for (std::size_t i = 0; i < hunk.lines.size(); ++i) {
        if (i != 0) out += ',';
        out += diffLineJson(hunk.lines[i]);
    }
    out += "]}";
    return out;
}

std::string diffFileJson(const DiffFile& file) {
    std::string out = "{";
    out += "\"oldPath\":";
    jsonAppendEscaped(out, file.oldPath);
    out += ",\"newPath\":";
    jsonAppendEscaped(out, file.newPath);
    out += ",\"kind\":";
    jsonAppendInt(out, static_cast<std::int64_t>(file.kind));
    out += ",\"oldMode\":";
    jsonAppendEscaped(out, file.oldMode);
    out += ",\"newMode\":";
    jsonAppendEscaped(out, file.newMode);
    out += ",\"oldBlob\":";
    jsonAppendEscaped(out, file.oldBlob);
    out += ",\"newBlob\":";
    jsonAppendEscaped(out, file.newBlob);
    out += ",\"binary\":";
    jsonAppendBool(out, file.binary);
    out += ",\"similarity\":";
    jsonAppendInt(out, file.similarity);
    out += ",\"addedLines\":";
    jsonAppendInt(out, file.addedLines);
    out += ",\"removedLines\":";
    jsonAppendInt(out, file.removedLines);
    out += ",\"displayPath\":";
    jsonAppendEscaped(out, file.displayPath());
    out += ",\"hunks\":[";
    for (std::size_t i = 0; i < file.hunks.size(); ++i) {
        if (i != 0) out += ',';
        out += diffHunkJson(file.hunks[i]);
    }
    out += "]}";
    return out;
}

}  // namespace

std::string toJson(const ParsedDiff& diff) {
    std::string out = "{\"files\":[";
    for (std::size_t i = 0; i < diff.files.size(); ++i) {
        if (i != 0) out += ',';
        out += diffFileJson(diff.files[i]);
    }
    out += "],\"truncated\":";
    jsonAppendBool(out, diff.truncated);
    out += ",\"inputBytes\":";
    jsonAppendInt(out, static_cast<std::int64_t>(diff.inputBytes));
    out += '}';
    return out;
}

}  // namespace gbm::capi
