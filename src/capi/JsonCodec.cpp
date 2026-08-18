#include "capi/JsonCodec.h"

#include "capi/JsonWriter.h"

#include <chrono>

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

std::string toJson(const Signature& sig) {
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
    out += toJson(meta.author);
    out += ",\"committer\":";
    out += toJson(meta.committer);
    out += ",\"subject\":";
    jsonAppendEscaped(out, meta.subject);
    out += ",\"body\":";
    jsonAppendEscaped(out, meta.body);
    out += ",\"signed\":";
    jsonAppendBool(out, meta.signedCommit);
    out += '}';
    return out;
}

std::string toJson(const std::vector<CommitMeta>& metas) {
    std::string out = "[";
    for (std::size_t i = 0; i < metas.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(metas[i]);
    }
    out += ']';
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
    // Omitted entirely (not emitted as "") when the operation didn't stamp a
    // kind -- keeps every unstamped outcome's JSON byte-identical to before
    // this field existed, so existing assertions on the exact payload shape
    // stay valid.
    if (!outcome.kind.empty()) {
        out += ",\"kind\":";
        jsonAppendEscaped(out, outcome.kind);
    }
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

std::string toJson(const BaseFolderRecord& record) {
    std::string out = "{";
    out += "\"id\":";
    jsonAppendInt(out, record.id);
    out += ",\"path\":";
    jsonAppendEscaped(out, record.path);
    out += ",\"enabled\":";
    jsonAppendBool(out, record.enabled);
    out += ",\"maxDepth\":";
    jsonAppendInt(out, record.maxDepth);
    out += ",\"followLinks\":";
    jsonAppendBool(out, record.followLinks);
    out += ",\"lastScanStarted\":";
    jsonAppendInt(out, record.lastScanStarted);
    out += ",\"lastScanFinished\":";
    jsonAppendInt(out, record.lastScanFinished);
    out += ",\"lastScanDirs\":";
    jsonAppendInt(out, record.lastScanDirs);
    out += ",\"lastScanMs\":";
    jsonAppendInt(out, record.lastScanMs);
    out += '}';
    return out;
}

std::string toJson(const std::vector<BaseFolderRecord>& records) {
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

/// The M6 Compare-tab file summary (CompareOps.h's CompareStore::compare())
/// reuses UnifiedDiffParser.h's DiffFile directly rather than introducing a
/// parallel type -- this is the array-of-DiffFile counterpart to
/// toJson(ParsedDiff) above, for a summary that has files but no wrapping
/// ParsedDiff (no truncated/inputBytes: those describe a single unified
/// diff blob, which compareFiles's two `git diff` invocations never
/// produce).
std::string toJson(const std::vector<DiffFile>& files) {
    std::string out = "[";
    for (std::size_t i = 0; i < files.size(); ++i) {
        if (i != 0) out += ',';
        out += diffFileJson(files[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const ChangedFile& file) {
    std::string out = "{";
    out += "\"path\":";
    jsonAppendEscaped(out, file.path);
    out += ",\"oldPath\":";
    jsonAppendEscaped(out, file.oldPath);
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
    out += ",\"similarity\":";
    jsonAppendInt(out, file.similarity);
    out += '}';
    return out;
}

std::string toJson(const std::vector<ChangedFile>& files) {
    std::string out = "[";
    for (std::size_t i = 0; i < files.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(files[i]);
    }
    out += "]";
    return out;
}

std::string toJson(const StashEntry& entry) {
    std::string out = "{";
    out += "\"index\":";
    jsonAppendInt(out, entry.index);
    out += ",\"message\":";
    jsonAppendEscaped(out, entry.message);
    out += ",\"oid\":";
    jsonAppendEscaped(out, entry.oid);
    out += ",\"timestamp\":";
    jsonAppendInt(out, entry.timestamp);
    out += '}';
    return out;
}

std::string toJson(const std::vector<StashEntry>& entries) {
    std::string out = "[";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(entries[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const WorktreeInfo& worktree) {
    std::string out = "{";
    out += "\"path\":";
    jsonAppendEscaped(out, worktree.path.string());
    out += ",\"headOid\":";
    jsonAppendEscaped(out, worktree.headOid);
    out += ",\"branch\":";
    jsonAppendEscaped(out, worktree.branch);
    out += ",\"isMain\":";
    jsonAppendBool(out, worktree.isMain);
    out += ",\"isBare\":";
    jsonAppendBool(out, worktree.isBare);
    out += ",\"isDetached\":";
    jsonAppendBool(out, worktree.isDetached);
    out += ",\"isLocked\":";
    jsonAppendBool(out, worktree.isLocked);
    out += ",\"lockReason\":";
    jsonAppendEscaped(out, worktree.lockReason);
    out += ",\"isPrunable\":";
    jsonAppendBool(out, worktree.isPrunable);
    out += ",\"prunableReason\":";
    jsonAppendEscaped(out, worktree.prunableReason);
    out += '}';
    return out;
}

std::string toJson(const std::vector<WorktreeInfo>& worktrees) {
    std::string out = "[";
    for (std::size_t i = 0; i < worktrees.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(worktrees[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const RemoteInfo& remote) {
    std::string out = "{";
    out += "\"name\":";
    jsonAppendEscaped(out, remote.name);
    out += ",\"fetchUrl\":";
    jsonAppendEscaped(out, remote.fetchUrl);
    out += ",\"pushUrl\":";
    jsonAppendEscaped(out, remote.pushUrl);
    out += '}';
    return out;
}

std::string toJson(const std::vector<RemoteInfo>& remotes) {
    std::string out = "[";
    for (std::size_t i = 0; i < remotes.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(remotes[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const RemotePrunePreviewEntry& entry) {
    std::string out = "{\"ref\":";
    jsonAppendEscaped(out, entry.ref);
    out += '}';
    return out;
}

std::string toJson(const std::vector<RemotePrunePreviewEntry>& entries) {
    std::string out = "[";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(entries[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const CompareCommitEntry& entry) {
    std::string out = "{\"oid\":";
    jsonAppendEscaped(out, entry.oid.hex());
    out += ",\"onRightOnly\":";
    jsonAppendBool(out, entry.onRightOnly);
    out += ",\"authorName\":";
    jsonAppendEscaped(out, entry.authorName);
    out += ",\"authorDate\":";
    jsonAppendInt(out, entry.authorDate);
    out += ",\"subject\":";
    jsonAppendEscaped(out, entry.subject);
    out += '}';
    return out;
}

std::string toJson(const std::vector<CompareCommitEntry>& entries) {
    std::string out = "[";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(entries[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const OperationRecord& record) {
    std::string out = "{";
    out += "\"whenEpochMs\":";
    jsonAppendInt(
        out,
        std::chrono::duration_cast<std::chrono::milliseconds>(record.when.time_since_epoch())
            .count());
    out += ",\"repoDir\":";
    jsonAppendEscaped(out, record.repoDir);
    out += ",\"argv\":[";
    for (std::size_t i = 0; i < record.argv.size(); ++i) {
        if (i != 0) out += ',';
        jsonAppendEscaped(out, record.argv[i]);
    }
    out += "],\"commandLine\":";
    jsonAppendEscaped(out, record.commandLine());
    out += ",\"exitCode\":";
    jsonAppendInt(out, record.exitCode);
    out += ",\"durationMs\":";
    jsonAppendInt(out, record.durationMs);
    out += ",\"stderrText\":";
    jsonAppendEscaped(out, record.stderrText);
    out += ",\"cancelled\":";
    jsonAppendBool(out, record.cancelled);
    out += ",\"timedOut\":";
    jsonAppendBool(out, record.timedOut);
    out += '}';
    return out;
}

namespace {

std::string blameLineJson(const BlameLine& line) {
    std::string out = "{";
    out += "\"commitOid\":";
    jsonAppendEscaped(out, line.commitOid.hex());
    out += ",\"authorName\":";
    jsonAppendEscaped(out, line.authorName);
    out += ",\"authorEmail\":";
    jsonAppendEscaped(out, line.authorEmail);
    out += ",\"authorTime\":";
    jsonAppendInt(out, line.authorTime);
    out += ",\"summary\":";
    jsonAppendEscaped(out, line.summary);
    out += ",\"finalLine\":";
    jsonAppendInt(out, line.finalLine);
    out += ",\"originalLine\":";
    jsonAppendInt(out, line.originalLine);
    out += ",\"content\":";
    jsonAppendEscaped(out, line.content);
    out += ",\"boundary\":";
    jsonAppendBool(out, line.boundary);
    out += '}';
    return out;
}

}  // namespace

std::string toJson(const BlameResult& result) {
    std::string out = "{\"lines\":[";
    for (std::size_t i = 0; i < result.lines.size(); ++i) {
        if (i != 0) out += ',';
        out += blameLineJson(result.lines[i]);
    }
    out += "],\"truncated\":";
    jsonAppendBool(out, result.truncated);
    out += '}';
    return out;
}

std::string toJson(const FileHistoryEntry& entry) {
    std::string out = "{";
    out += "\"oid\":";
    jsonAppendEscaped(out, entry.oid.hex());
    out += ",\"author\":";
    out += toJson(entry.author);
    out += ",\"subject\":";
    jsonAppendEscaped(out, entry.subject);
    out += ",\"status\":";
    jsonAppendEscaped(out, entry.status);
    out += ",\"renamedFrom\":";
    jsonAppendEscaped(out, entry.renamedFrom);
    out += '}';
    return out;
}

std::string toJson(const std::vector<FileHistoryEntry>& entries) {
    std::string out = "[";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(entries[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const LineHistoryChunk& chunk) {
    std::string out = "{";
    out += "\"oid\":";
    jsonAppendEscaped(out, chunk.oid.hex());
    out += ",\"author\":";
    out += toJson(chunk.author);
    out += ",\"subject\":";
    jsonAppendEscaped(out, chunk.subject);
    out += ",\"diffText\":";
    jsonAppendEscaped(out, chunk.diffText);
    out += '}';
    return out;
}

std::string toJson(const std::vector<LineHistoryChunk>& chunks) {
    std::string out = "[";
    for (std::size_t i = 0; i < chunks.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(chunks[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const ReflogEntry& entry) {
    std::string out = "{";
    out += "\"index\":";
    jsonAppendInt(out, entry.index);
    out += ",\"oid\":";
    jsonAppendEscaped(out, entry.oid.hex());
    out += ",\"message\":";
    jsonAppendEscaped(out, entry.message);
    out += ",\"who\":";
    out += toJson(entry.who);
    out += '}';
    return out;
}

std::string toJson(const std::vector<ReflogEntry>& entries) {
    std::string out = "[";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(entries[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const OperationRunner::UndoEntry& entry) {
    std::string out = "{";
    out += "\"id\":";
    jsonAppendInt(out, static_cast<std::int64_t>(entry.id));
    out += ",\"description\":";
    jsonAppendEscaped(out, entry.description);
    out += ",\"headBefore\":";
    jsonAppendEscaped(out, entry.headBefore.hex());
    out += ",\"branchBefore\":";
    jsonAppendEscaped(out, entry.branchBefore);
    out += ",\"timestamp\":";
    jsonAppendInt(out, entry.timestamp);
    out += '}';
    return out;
}

std::string toJson(const std::vector<OperationRunner::UndoEntry>& entries) {
    std::string out = "[";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(entries[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const std::vector<std::string>& strings) {
    std::string out = "[";
    for (std::size_t i = 0; i < strings.size(); ++i) {
        if (i != 0) out += ',';
        jsonAppendEscaped(out, strings[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const CleanEntry& entry) {
    std::string out = "{";
    out += "\"path\":";
    jsonAppendEscaped(out, entry.path);
    out += ",\"isDirectory\":";
    jsonAppendBool(out, entry.isDirectory);
    out += '}';
    return out;
}

std::string toJson(const std::vector<CleanEntry>& entries) {
    std::string out = "[";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(entries[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const RebaseTodoEntry& entry) {
    std::string out = "{";
    out += "\"action\":";
    jsonAppendInt(out, static_cast<std::int64_t>(entry.action));
    out += ",\"oid\":";
    jsonAppendEscaped(out, entry.oid.hex());
    out += ",\"shortOid\":";
    jsonAppendEscaped(out, entry.shortOid);
    out += ",\"subject\":";
    jsonAppendEscaped(out, entry.subject);
    out += '}';
    return out;
}

std::string toJson(const std::vector<RebaseTodoEntry>& entries) {
    std::string out = "[";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(entries[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const SubmoduleInfo& submodule) {
    std::string out = "{";
    out += "\"name\":";
    jsonAppendEscaped(out, submodule.name);
    out += ",\"path\":";
    jsonAppendEscaped(out, submodule.path);
    out += ",\"url\":";
    jsonAppendEscaped(out, submodule.url);
    out += ",\"branch\":";
    jsonAppendEscaped(out, submodule.branch);
    out += ",\"headOid\":";
    jsonAppendEscaped(out, submodule.headOid);
    out += ",\"state\":";
    jsonAppendInt(out, static_cast<std::int64_t>(submodule.state));
    out += '}';
    return out;
}

std::string toJson(const std::vector<SubmoduleInfo>& submodules) {
    std::string out = "[";
    for (std::size_t i = 0; i < submodules.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(submodules[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const BisectStatus& status) {
    std::string out = "{";
    out += "\"active\":";
    jsonAppendBool(out, status.active);
    out += ",\"currentOid\":";
    jsonAppendEscaped(out, status.currentOid);
    out += ",\"badOid\":";
    jsonAppendEscaped(out, status.badOid);
    out += ",\"goodOids\":";
    out += toJson(status.goodOids);
    out += ",\"skippedOids\":";
    out += toJson(status.skippedOids);
    out += ",\"logText\":";
    jsonAppendEscaped(out, status.logText);
    out += '}';
    return out;
}

std::string toJson(const LfsInstallation& installation) {
    std::string out = "{";
    out += "\"available\":";
    jsonAppendBool(out, installation.available);
    out += ",\"version\":";
    jsonAppendEscaped(out, installation.version);
    out += '}';
    return out;
}

std::string toJson(const LfsFileInfo& file) {
    std::string out = "{";
    out += "\"path\":";
    jsonAppendEscaped(out, file.path);
    out += ",\"oid\":";
    jsonAppendEscaped(out, file.oid);
    out += ",\"downloadedLocally\":";
    jsonAppendBool(out, file.downloadedLocally);
    out += '}';
    return out;
}

std::string toJson(const std::vector<LfsFileInfo>& files) {
    std::string out = "[";
    for (std::size_t i = 0; i < files.size(); ++i) {
        if (i != 0) out += ',';
        out += toJson(files[i]);
    }
    out += ']';
    return out;
}

std::string toJson(const LocalIdentity& identity) {
    std::string out = "{";
    out += "\"name\":";
    jsonAppendEscaped(out, identity.name);
    out += ",\"email\":";
    jsonAppendEscaped(out, identity.email);
    out += ",\"overridden\":";
    jsonAppendBool(out, identity.overridden);
    out += '}';
    return out;
}

std::string toJson(const EffectiveIdentity& identity) {
    std::string out = "{";
    out += "\"name\":";
    jsonAppendEscaped(out, identity.name);
    out += ",\"email\":";
    jsonAppendEscaped(out, identity.email);
    out += '}';
    return out;
}

namespace {

std::string conflictSegmentJson(const ConflictSegment& segment) {
    std::string out = "{\"kind\":";
    jsonAppendInt(out, static_cast<std::int64_t>(segment.kind));
    out += ",\"lines\":";
    out += toJson(segment.lines);
    out += ",\"ours\":";
    out += toJson(segment.ours);
    out += ",\"theirs\":";
    out += toJson(segment.theirs);
    out += ",\"base\":";
    out += toJson(segment.base);
    out += ",\"hasBase\":";
    jsonAppendBool(out, segment.hasBase);
    out += '}';
    return out;
}

}  // namespace

std::string toJson(const ParsedConflictFile& parsed) {
    std::string out = "{\"segments\":[";
    for (std::size_t i = 0; i < parsed.segments.size(); ++i) {
        if (i != 0) out += ',';
        out += conflictSegmentJson(parsed.segments[i]);
    }
    out += "],\"regionCount\":";
    jsonAppendInt(out, static_cast<std::int64_t>(parsed.regionCount));
    out += ",\"wellFormed\":";
    jsonAppendBool(out, parsed.wellFormed);
    out += '}';
    return out;
}

}  // namespace gbm::capi
