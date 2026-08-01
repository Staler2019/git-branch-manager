#include "app/bridge/RepositorySession.h"

#include "core/base/Logging.h"
#include "core/git/AskpassHelper.h"

#include <QMetaObject>
#include <QMetaType>

#include <utility>

namespace gbm {

RepositorySession::RepositorySession(GitInstallation installation,
                                     RepoPaths paths,
                                     ThreadPool& readPool,
                                     QObject* parent)
    : QObject(parent),
      installation_(std::move(installation)),
      paths_(std::move(paths)),
      readPool_(readPool) {
    runner_ = makeProcessRunner(installation_.executable);
    catFile_ = std::make_unique<CatFileBatch>(installation_.executable, paths_);
    refStore_ = std::make_unique<RefStore>(*runner_, paths_);
    history_ = std::make_unique<HistoryProvider>(*runner_, paths_);
    diffs_ = std::make_unique<DiffService>(*runner_, paths_);
    operations_ = std::make_unique<OperationRunner>(*runner_, paths_);
    workingCopyStatusReader_ = std::make_unique<WorkingCopyStatusReader>(*runner_, paths_);
    stashStore_ = std::make_unique<StashStore>(*runner_, paths_);
    worktreeStore_ = std::make_unique<WorktreeStore>(*runner_, paths_);
    remoteStore_ = std::make_unique<RemoteStore>(*runner_, paths_);
    blameStore_ = std::make_unique<BlameStore>(*runner_, paths_);
    fileHistoryStore_ = std::make_unique<FileHistoryStore>(*runner_, paths_);
    reflogStore_ = std::make_unique<ReflogStore>(*runner_, paths_);
    submoduleStore_ = std::make_unique<SubmoduleStore>(*runner_, paths_);
    bisectStore_ = std::make_unique<BisectStore>(*runner_, paths_);
    lfsStore_ = std::make_unique<LfsStore>(*runner_, paths_);

    askpass_ = new AskpassWatcher(this);
    connect(
        askpass_, &AskpassWatcher::promptReceived, this, &RepositorySession::credentialRequested);
}

RepositorySession::~RepositorySession() {
    // Cancel first, then let the members go: a worker still holding a reference to
    // this session's services must not outlive them.
    historyCancel_.cancel();
    readCancel_.cancel();
    if (catFile_) {
        catFile_->stop();
    }
}

QString RepositorySession::displayName() const {
    return QString::fromStdString(paths_.displayName());
}

RepoState RepositorySession::state() const {
    return RepoState::read(paths_);
}

void RepositorySession::setBusy(bool busy) {
    // Reference-counted: several reads may be in flight, and the indicator should
    // only clear when the last one finishes.
    const bool wasBusy = busyCount_ > 0;
    busyCount_ += busy ? 1 : -1;
    if (busyCount_ < 0) {
        busyCount_ = 0;
    }
    const bool isBusy = busyCount_ > 0;
    if (isBusy != wasBusy) {
        emit busyChanged(isBusy);
    }
}

void RepositorySession::refreshHistory(HistoryQuery query) {
    // Supersede rather than queue: the previous walk's results are no longer what
    // the user is looking at.
    historyCancel_.cancel();
    historyCancel_ = CancellationSource();
    const CancellationToken token = historyCancel_.token();

    setBusy(true);

    readPool_.post([this, query = std::move(query), token]() mutable {
        // If no explicit tips were given, seed from the refs we already have so the
        // trunk lands in lane 0.
        if (query.includeRefs.empty()) {
            if (auto refs = refs_.current()) {
                query.includeRefs = RefStore::historySeedRefs(*refs);
            }
        }

        auto result = history_->walk(
            query,
            [this, token](GraphSnapshotPtr chunk) {
                if (token.isCancelled()) {
                    return;
                }
                const bool complete = chunk->complete;
                graph_.publish(std::move(chunk));
                // Queued, so the UI thread picks it up in its own event loop.
                QMetaObject::invokeMethod(
                    this, [this, complete] { emit graphUpdated(complete); }, Qt::QueuedConnection);
            },
            token);

        if (!result && result.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(result).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::refreshRefs() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto snapshot = refStore_->load(token);
        if (snapshot) {
            refs_.publish(*snapshot);
            QMetaObject::invokeMethod(this, [this] { emit refsUpdated(); }, Qt::QueuedConnection);
        } else if (snapshot.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(snapshot).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::requestCommitMetadata(std::vector<ObjectId> oids) {
    if (oids.empty()) {
        return;
    }
    const CancellationToken token = readCancel_.token();

    // postFront: the newest request reflects where the user is actually looking,
    // so it must jump ahead of stale viewport requests still in the queue.
    readPool_.postFront([this, oids = std::move(oids), token] {
        if (token.isCancelled()) {
            return;
        }
        if (auto started = catFile_->start(); !started) {
            GitError error = std::move(started).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
            return;
        }
        std::vector<CommitMeta> metadata = catFile_->readCommits(oids);
        if (token.isCancelled() || metadata.empty()) {
            return;
        }
        QMetaObject::invokeMethod(
            this,
            [this, metadata = std::move(metadata)] { emit commitMetadataReady(metadata); },
            Qt::QueuedConnection);
    });
}

void RepositorySession::requestCommitDetails(const ObjectId& commit) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, commit, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        const DiffOptions options;
        auto files = diffs_->changedFiles(commit, options, token);
        auto diff = diffs_->commitDiff(commit, options, token);

        if (!token.isCancelled() && files && diff) {
            auto filesPtr = *files;
            auto diffPtr = *diff;
            QMetaObject::invokeMethod(
                this,
                [this, commit, filesPtr, diffPtr] {
                    emit commitDetailsReady(commit, filesPtr, diffPtr);
                },
                Qt::QueuedConnection);
        } else if (files && !files->get()) {
            // Nothing to show; not an error worth a dialog.
        } else if (!files && files.error().code != GitError::Code::Cancelled) {
            GitError error = files.error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }

        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::checkout(const CheckoutRequest& request) {
    setBusy(true);
    operations_->submit(makeCheckoutOperation(request), [this](OperationOutcome outcome) {
        // Runs on the operation runner's serial thread; hop to the UI thread and
        // refresh what the checkout changed.
        QMetaObject::invokeMethod(
            this,
            [this, outcome = std::move(outcome)] {
                setBusy(false);
                emit operationFinished(outcome);
                if (outcome.succeeded) {
                    refreshRefs();
                    refreshHistory();
                }
            },
            Qt::QueuedConnection);
    });
}

// --- Sidebar (Phase 2): branch mutation -------------------------------------

void RepositorySession::createBranch(const CreateBranchRequest& request) {
    submitAndRefresh(makeCreateBranchOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::renameBranch(const RenameBranchRequest& request) {
    submitAndRefresh(makeRenameBranchOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::deleteBranch(const DeleteBranchRequest& request) {
    // Unlike FetchRequest/PushRequest/DeleteTagRequest, DeleteBranchRequest has
    // no askpassDir field -- DeleteBranchOperation's `git push --delete` path
    // (core/git/ops/BranchOps.cpp) never calls askpass::wire(). Adding that
    // field is a src/core change and out of scope here, so a remote delete
    // that needs credentials fails the same way an unauthenticated push
    // would (GIT_TERMINAL_PROMPT=0), rather than prompting.
    submitAndRefresh(makeDeleteBranchOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::cancelPendingReads() {
    readCancel_.cancel();
    readCancel_ = CancellationSource();
}

void RepositorySession::refreshWorkingCopyStatus() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto status = workingCopyStatusReader_->read(token);
        if (status) {
            workingCopyStatus_.publish(*status);
            QMetaObject::invokeMethod(
                this, [this] { emit workingCopyStatusUpdated(); }, Qt::QueuedConnection);
        } else if (status.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(status).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::requestWorkingCopyDiff(const std::string& path, bool staged) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    // postFront: mirrors requestCommitDetails -- the newest selection is what
    // the user is looking at, so it must not wait behind a stale request.
    readPool_.postFront([this, path, staged, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        auto diff = diffs_->workingTreeDiff(staged, {path}, DiffOptions{}, token);
        if (diff) {
            auto diffPtr = *diff;
            const QString qpath = QString::fromStdString(path);
            QMetaObject::invokeMethod(
                this,
                [this, qpath, staged, diffPtr] {
                    emit workingCopyDiffReady(qpath, staged, diffPtr);
                },
                Qt::QueuedConnection);
        } else if (diff.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(diff).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::requestCompareWithWorkingCopy(const ObjectId& commit) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    // postFront: mirrors requestWorkingCopyDiff -- the newest request is what
    // the user is looking at.
    readPool_.postFront([this, commit, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        auto diff = diffs_->commitVsWorkingTree(commit, DiffOptions{}, token);
        if (diff) {
            auto diffPtr = *diff;
            QMetaObject::invokeMethod(
                this,
                [this, commit, diffPtr] { emit compareWithWorkingCopyReady(commit, diffPtr); },
                Qt::QueuedConnection);
        } else if (diff.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(diff).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::submitWorkingCopyOperation(std::unique_ptr<Operation> operation,
                                                   bool alsoRefreshHistory) {
    setBusy(true);
    operations_->submit(std::move(operation), [this, alsoRefreshHistory](OperationOutcome outcome) {
        // Runs on the operation runner's serial thread; hop to the UI thread
        // before touching anything Qt.
        QMetaObject::invokeMethod(
            this,
            [this, outcome = std::move(outcome), alsoRefreshHistory] {
                setBusy(false);
                emit workingCopyOperationFinished(outcome);
                if (outcome.succeeded) {
                    refreshWorkingCopyStatus();
                    if (alsoRefreshHistory) {
                        // A commit moved HEAD, so both the ref list and the
                        // graph need to reflect it.
                        refreshRefs();
                        refreshHistory();
                    }
                }
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::stageFiles(std::vector<std::string> paths) {
    StageFilesRequest request;
    request.paths = std::move(paths);
    submitWorkingCopyOperation(makeStageFilesOperation(std::move(request)), false);
}

void RepositorySession::unstageFiles(std::vector<std::string> paths) {
    UnstageFilesRequest request;
    request.paths = std::move(paths);
    submitWorkingCopyOperation(makeUnstageFilesOperation(std::move(request)), false);
}

void RepositorySession::applyPatch(std::string patch, bool reverse) {
    ApplyPatchRequest request;
    request.patch = std::move(patch);
    request.reverse = reverse;
    submitWorkingCopyOperation(makeApplyPatchOperation(std::move(request)), false);
}

void RepositorySession::commitChanges(const CommitRequest& request) {
    submitWorkingCopyOperation(makeCommitOperation(request), true);
}

void RepositorySession::mergeBranch(const MergeRequest& request) {
    submitWorkingCopyOperation(makeMergeOperation(request), true);
}

void RepositorySession::abortMerge() {
    submitWorkingCopyOperation(makeMergeAbortOperation(), true);
}

void RepositorySession::cherryPick(const CherryPickRequest& request) {
    submitWorkingCopyOperation(makeCherryPickOperation(request), true);
}

void RepositorySession::continueCherryPick() {
    submitWorkingCopyOperation(makeCherryPickContinueOperation(), true);
}

void RepositorySession::skipCherryPick() {
    submitWorkingCopyOperation(makeCherryPickSkipOperation(), true);
}

void RepositorySession::abortCherryPick() {
    submitWorkingCopyOperation(makeCherryPickAbortOperation(), true);
}

void RepositorySession::revertCommit(const RevertRequest& request) {
    submitWorkingCopyOperation(makeRevertOperation(request), true);
}

void RepositorySession::resolveConflict(const ResolveConflictRequest& request) {
    // Never moves HEAD, so no refreshRefs/refreshHistory -- just the
    // working-copy status, to update the conflicted list.
    submitWorkingCopyOperation(makeResolveConflictOperation(request), false);
}

void RepositorySession::requestConflictSides(const std::string& path,
                                             const std::string& ancestorBlob,
                                             const std::string& oursBlob,
                                             const std::string& theirsBlob) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, ancestorBlob, oursBlob, theirsBlob, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        if (auto started = catFile_->start(); !started) {
            GitError error = std::move(started).error();
            QMetaObject::invokeMethod(
                this,
                [this, error] {
                    setBusy(false);
                    emit errorOccurred(error);
                },
                Qt::QueuedConnection);
            return;
        }

        // Best-effort: a stage that fails to read (or does not exist) shows as
        // empty rather than failing the whole request, so the two sides that
        // did read are still shown.
        auto readOrEmpty = [this](const std::string& blob) {
            if (blob.empty()) {
                return std::string();
            }
            auto object = catFile_->read(blob);
            return object ? object->content : std::string();
        };
        const std::string ancestor = readOrEmpty(ancestorBlob);
        const std::string ours = readOrEmpty(oursBlob);
        const std::string theirs = readOrEmpty(theirsBlob);

        const QString qpath = QString::fromStdString(path);
        QMetaObject::invokeMethod(
            this,
            [this, qpath, ancestor, ours, theirs] {
                setBusy(false);
                emit conflictSidesReady(qpath,
                                        QString::fromStdString(ancestor),
                                        QString::fromStdString(ours),
                                        QString::fromStdString(theirs));
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::submitAndRefresh(std::unique_ptr<Operation> operation,
                                         std::function<void(bool)> afterFinished) {
    setBusy(true);
    operations_->submit(std::move(operation),
                        [this, afterFinished = std::move(afterFinished)](OperationOutcome outcome) {
                            // Runs on the operation runner's serial thread; hop to the UI
                            // thread before touching anything Qt, same as
                            // submitWorkingCopyOperation.
                            QMetaObject::invokeMethod(
                                this,
                                [this, outcome = std::move(outcome), afterFinished] {
                                    setBusy(false);
                                    emit workingCopyOperationFinished(outcome);
                                    if (afterFinished) {
                                        afterFinished(outcome.succeeded);
                                    }
                                },
                                Qt::QueuedConnection);
                        });
}

// --- M3: stashes -------------------------------------------------------

void RepositorySession::refreshStashes() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto list = stashStore_->list(token);
        if (list) {
            stashes_.publish(std::make_shared<std::vector<StashEntry>>(std::move(*list)));
            QMetaObject::invokeMethod(
                this, [this] { emit stashesUpdated(); }, Qt::QueuedConnection);
        } else if (list.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(list).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::saveStash(const StashSaveRequest& request) {
    submitAndRefresh(makeStashSaveOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorkingCopyStatus();
            refreshStashes();
        }
    });
}

void RepositorySession::applyStash(const StashApplyRequest& request) {
    submitAndRefresh(makeStashApplyOperation(request), [this](bool succeeded) {
        // Even a conflicting apply/pop leaves the working tree changed.
        refreshWorkingCopyStatus();
        if (succeeded) {
            refreshStashes();
        }
    });
}

void RepositorySession::dropStash(const StashDropRequest& request) {
    submitAndRefresh(makeStashDropOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshStashes();
        }
    });
}

void RepositorySession::branchFromStash(const StashBranchRequest& request) {
    submitAndRefresh(makeStashBranchOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorkingCopyStatus();
            refreshStashes();
            refreshRefs();
            refreshHistory();
        }
    });
}

// --- M3: tags ------------------------------------------------------------

void RepositorySession::createTag(const CreateTagRequest& request) {
    submitAndRefresh(makeCreateTagOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::deleteTag(const DeleteTagRequest& request) {
    DeleteTagRequest wired = request;
    if (wired.alsoRemote) {
        wired.askpassDir = askpass::makeRequestDir();
        if (!wired.askpassDir.empty()) {
            askpass_->start(wired.askpassDir);
        }
    }
    submitAndRefresh(makeDeleteTagOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::pushTag(const PushTagRequest& request) {
    PushTagRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makePushTagOperation(wired), [this](bool) { askpass_->stop(); });
}

// --- M3: worktrees ---------------------------------------------------------

void RepositorySession::refreshWorktrees() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto list = worktreeStore_->list(token);
        if (list) {
            worktrees_.publish(std::make_shared<std::vector<WorktreeInfo>>(std::move(*list)));
            QMetaObject::invokeMethod(
                this, [this] { emit worktreesUpdated(); }, Qt::QueuedConnection);
        } else if (list.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(list).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::addWorktree(const AddWorktreeRequest& request) {
    submitAndRefresh(makeAddWorktreeOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

void RepositorySession::removeWorktree(const RemoveWorktreeRequest& request) {
    submitAndRefresh(makeRemoveWorktreeOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

void RepositorySession::pruneWorktrees() {
    submitAndRefresh(makePruneWorktreesOperation(PruneWorktreesRequest{}), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

void RepositorySession::lockWorktree(const LockWorktreeRequest& request) {
    submitAndRefresh(makeLockWorktreeOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

void RepositorySession::unlockWorktree(const UnlockWorktreeRequest& request) {
    submitAndRefresh(makeUnlockWorktreeOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

// --- M3: remotes -----------------------------------------------------------

void RepositorySession::refreshRemotes() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto list = remoteStore_->list(token);
        if (list) {
            remotes_.publish(std::make_shared<std::vector<RemoteInfo>>(std::move(*list)));
            QMetaObject::invokeMethod(
                this, [this] { emit remotesUpdated(); }, Qt::QueuedConnection);
        } else if (list.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(list).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::fetchRemote(FetchRequest request) {
    request.askpassDir = askpass::makeRequestDir();
    if (!request.askpassDir.empty()) {
        askpass_->start(request.askpassDir);
    }
    submitAndRefresh(makeFetchOperation(std::move(request)), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::pullChanges(PullRequest request) {
    request.askpassDir = askpass::makeRequestDir();
    if (!request.askpassDir.empty()) {
        askpass_->start(request.askpassDir);
    }
    submitAndRefresh(makePullOperation(std::move(request)), [this](bool succeeded) {
        askpass_->stop();
        refreshWorkingCopyStatus();
        if (succeeded) {
            refreshRefs();
            refreshHistory();
        }
    });
}

void RepositorySession::pushChanges(PushRequest request) {
    request.askpassDir = askpass::makeRequestDir();
    if (!request.askpassDir.empty()) {
        askpass_->start(request.askpassDir);
    }
    submitAndRefresh(makePushOperation(std::move(request)), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::provideCredential(const QString& secret) {
    askpass_->answer(secret);
}

void RepositorySession::cancelCredential() {
    askpass_->cancel();
}

// --- M4: reset / restore / clean --------------------------------------------

void RepositorySession::resetTo(const ResetRequest& request) {
    submitWorkingCopyOperation(makeResetOperation(request), true);
}

void RepositorySession::restorePaths(const RestoreRequest& request) {
    submitWorkingCopyOperation(makeRestoreOperation(request), false);
}

void RepositorySession::requestCleanPreview(bool includeIgnored) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, includeIgnored, token] {
        CleanPreviewer previewer(*runner_, paths_);
        auto preview = previewer.preview(includeIgnored, token);
        if (preview) {
            auto entries = *preview;
            QMetaObject::invokeMethod(
                this,
                [this, entries = std::move(entries)] { emit cleanPreviewReady(entries); },
                Qt::QueuedConnection);
        } else if (preview.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(preview).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::cleanUntracked(const CleanRequest& request) {
    submitWorkingCopyOperation(makeCleanOperation(request), false);
}

// --- M4: rebase --------------------------------------------------------------

void RepositorySession::requestRebasePlan(const std::string& upstream) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, upstream, token] {
        RebasePlanner planner(*runner_, paths_);
        auto plan = planner.plan(upstream, token);
        if (plan) {
            auto entries = *plan;
            QMetaObject::invokeMethod(
                this,
                [this, entries = std::move(entries)] { emit rebasePlanReady(entries); },
                Qt::QueuedConnection);
        } else if (plan.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(plan).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::startInteractiveRebase(const RebaseInteractiveRequest& request) {
    submitWorkingCopyOperation(makeRebaseInteractiveOperation(request), true);
}

void RepositorySession::startRebase(const RebaseRequest& request) {
    submitWorkingCopyOperation(makeRebaseOperation(request), true);
}

void RepositorySession::continueRebase() {
    submitWorkingCopyOperation(makeRebaseContinueOperation(), true);
}

void RepositorySession::skipRebase() {
    submitWorkingCopyOperation(makeRebaseSkipOperation(), true);
}

void RepositorySession::abortRebase() {
    submitWorkingCopyOperation(makeRebaseAbortOperation(), true);
}

// --- M4: blame -----------------------------------------------------------------

void RepositorySession::requestBlame(const std::string& path,
                                     const std::string& revision,
                                     int startLine,
                                     int endLine) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, revision, startLine, endLine, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        auto result = blameStore_->blame(path, revision, startLine, endLine, token);
        if (result) {
            auto resultPtr = *result;
            QMetaObject::invokeMethod(
                this, [this, resultPtr] { emit blameReady(resultPtr); }, Qt::QueuedConnection);
        } else if (result.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(result).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

// --- M4: file and line history ------------------------------------------------

void RepositorySession::requestFileHistory(const std::string& path,
                                           const std::string& startRevision) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, startRevision, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        auto entries = fileHistoryStore_->fileHistory(path, startRevision, token);
        if (entries) {
            auto result = *entries;
            QMetaObject::invokeMethod(
                this,
                [this, result = std::move(result)] { emit fileHistoryReady(result); },
                Qt::QueuedConnection);
        } else if (entries.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(entries).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::requestLineHistory(const std::string& path,
                                           int startLine,
                                           int endLine,
                                           const std::string& startRevision) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, startLine, endLine, startRevision, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        auto chunks =
            fileHistoryStore_->lineHistory(path, startLine, endLine, startRevision, token);
        if (chunks) {
            auto result = *chunks;
            QMetaObject::invokeMethod(
                this,
                [this, result = std::move(result)] { emit lineHistoryReady(result); },
                Qt::QueuedConnection);
        } else if (chunks.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(chunks).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

// --- M4: reflog and undo --------------------------------------------------------

void RepositorySession::requestReflog(const std::string& ref) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, ref, token] {
        auto entries = reflogStore_->list(ref, token);
        if (entries) {
            auto result = *entries;
            QMetaObject::invokeMethod(
                this,
                [this, result = std::move(result)] { emit reflogReady(result); },
                Qt::QueuedConnection);
        } else if (entries.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(entries).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::undoLastOperation() {
    const auto& journal = operations_->undoJournal();
    if (journal.empty()) {
        return;
    }
    const auto& last = journal.back();
    UndoRequest request;
    request.headBefore = last.headBefore;
    request.branchBefore = last.branchBefore;
    submitWorkingCopyOperation(makeUndoOperation(request), true);
}

// --- M5: submodules ----------------------------------------------------------

void RepositorySession::refreshSubmodules() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto list = submoduleStore_->list(token);
        if (list) {
            submodules_.publish(std::make_shared<std::vector<SubmoduleInfo>>(std::move(*list)));
            QMetaObject::invokeMethod(
                this, [this] { emit submodulesUpdated(); }, Qt::QueuedConnection);
        } else if (list.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(list).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::addSubmodule(const AddSubmoduleRequest& request) {
    AddSubmoduleRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makeAddSubmoduleOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

void RepositorySession::initSubmodules(const SubmodulePathsRequest& request) {
    submitAndRefresh(makeInitSubmodulesOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

void RepositorySession::updateSubmodules(const UpdateSubmodulesRequest& request) {
    UpdateSubmodulesRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makeUpdateSubmodulesOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

void RepositorySession::syncSubmodules(const SubmodulePathsRequest& request) {
    submitAndRefresh(makeSyncSubmodulesOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

void RepositorySession::deinitSubmodules(const DeinitSubmodulesRequest& request) {
    submitAndRefresh(makeDeinitSubmodulesOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

// --- M5: bisect ----------------------------------------------------------

void RepositorySession::refreshBisectStatus() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto status = bisectStore_->status(token);
        if (status) {
            bisectStatus_.publish(std::make_shared<BisectStatus>(std::move(*status)));
            QMetaObject::invokeMethod(
                this, [this] { emit bisectStatusUpdated(); }, Qt::QueuedConnection);
        } else if (status.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(status).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::startBisect(const BisectStartRequest& request) {
    submitAndRefresh(makeBisectStartOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshBisectStatus();
        }
    });
}

void RepositorySession::markBisect(const BisectMarkRequest& request) {
    submitAndRefresh(makeBisectMarkOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshBisectStatus();
        }
    });
}

void RepositorySession::skipBisect(const BisectSkipRequest& request) {
    submitAndRefresh(makeBisectSkipOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshBisectStatus();
        }
    });
}

void RepositorySession::resetBisect(const BisectResetRequest& request) {
    submitAndRefresh(makeBisectResetOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshBisectStatus();
        }
    });
}

// --- M5: LFS ---------------------------------------------------------------

void RepositorySession::refreshLfs() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto installation = detectLfs(*runner_, paths_, token);
        if (!installation) {
            if (installation.error().code != GitError::Code::Cancelled) {
                GitError error = std::move(installation).error();
                QMetaObject::invokeMethod(
                    this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
            }
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        const bool available = installation->available;
        LfsInstallation installationValue = *installation;
        QMetaObject::invokeMethod(
            this,
            [this, installationValue] { lfsInstallation_ = installationValue; },
            Qt::QueuedConnection);

        if (!available) {
            QMetaObject::invokeMethod(
                this,
                [this] {
                    emit lfsUpdated();
                    setBusy(false);
                },
                Qt::QueuedConnection);
            return;
        }

        auto patterns = lfsStore_->trackedPatterns(token);
        if (patterns) {
            lfsPatterns_.publish(std::make_shared<std::vector<std::string>>(std::move(*patterns)));
        }
        auto files = lfsStore_->listFiles(token);
        if (files) {
            lfsFiles_.publish(std::make_shared<std::vector<LfsFileInfo>>(std::move(*files)));
        }
        QMetaObject::invokeMethod(
            this,
            [this] {
                emit lfsUpdated();
                setBusy(false);
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::installLfs() {
    submitAndRefresh(makeLfsInstallOperation(), [this](bool succeeded) {
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::trackLfsPattern(const LfsTrackRequest& request) {
    submitAndRefresh(makeLfsTrackOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::untrackLfsPattern(const LfsUntrackRequest& request) {
    submitAndRefresh(makeLfsUntrackOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::pullLfs(const LfsTransferRequest& request) {
    LfsTransferRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makeLfsPullOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::fetchLfs(const LfsTransferRequest& request) {
    LfsTransferRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makeLfsFetchOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::pruneLfs(const LfsPruneRequest& request) {
    submitAndRefresh(makeLfsPruneOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshLfs();
        }
    });
}

// --- M5: patch import/export ------------------------------------------------

void RepositorySession::exportPatches(const ExportPatchesRequest& request) {
    submitAndRefresh(makeExportPatchesOperation(request), nullptr);
}

void RepositorySession::applyPatchFiles(const ApplyPatchFilesRequest& request) {
    submitWorkingCopyOperation(makeApplyPatchFilesOperation(request), false);
}

void RepositorySession::importPatches(const ImportPatchesRequest& request) {
    submitWorkingCopyOperation(makeImportPatchesOperation(request), true);
}

void RepositorySession::continueImport() {
    submitWorkingCopyOperation(makeAmContinueOperation(), true);
}

void RepositorySession::skipImport() {
    submitWorkingCopyOperation(makeAmSkipOperation(), true);
}

void RepositorySession::abortImport() {
    submitWorkingCopyOperation(makeAmAbortOperation(), true);
}

}  // namespace gbm
