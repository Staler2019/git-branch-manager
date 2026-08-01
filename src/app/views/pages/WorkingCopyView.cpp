#include "app/views/pages/WorkingCopyView.h"

#include "app/bridge/RepositorySession.h"
#include "app/views/SideBySideDiffView.h"
#include "core/git/ops/CommitOps.h"
#include "core/git/ops/ConflictOps.h"
#include "core/git/ops/ResetOps.h"

#include <QCheckBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QMenu>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSplitter>
#include <QStackedWidget>
#include <QVBoxLayout>

namespace gbm {

namespace {

/// "old -> new" for a rename/copy, otherwise just the path.
QString pathLabel(const WorkingCopyEntry& entry) {
    if (!entry.oldPath.empty()) {
        return QString::fromStdString(entry.oldPath) + QStringLiteral("  →  ") +
               QString::fromStdString(entry.path);
    }
    return QString::fromStdString(entry.path);
}

/// Qt::UserRole+1 on an unstaged-list item: whether it is untracked, i.e. has
/// no HEAD/index content for `git restore` to discard back to.
constexpr int kUntrackedRole = Qt::UserRole + 1;

QListWidgetItem* addEntry(QListWidget* list,
                          const WorkingCopyEntry& entry,
                          const QString& suffix,
                          bool untracked = false) {
    auto* item = new QListWidgetItem(pathLabel(entry) + suffix, list);
    item->setData(Qt::UserRole, QString::fromStdString(entry.path));
    item->setData(kUntrackedRole, untracked);
    return item;
}

}  // namespace

WorkingCopyView::WorkingCopyView(QWidget* parent) : QWidget(parent) {
    buildUi();
    rebuildLists();
}

void WorkingCopyView::buildUi() {
    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(6, 6, 6, 6);

    summaryLabel_ = new QLabel(tr("No repository open"), this);
    outerLayout->addWidget(summaryLabel_);

    auto* splitter = new QSplitter(Qt::Horizontal, this);

    auto* leftWidget = new QWidget(splitter);
    auto* leftLayout = new QVBoxLayout(leftWidget);
    leftLayout->setContentsMargins(0, 0, 0, 0);

    conflictedGroup_ = new QWidget(leftWidget);
    auto* conflictedLayout = new QVBoxLayout(conflictedGroup_);
    conflictedLayout->setContentsMargins(0, 0, 0, 0);
    conflictedLayout->addWidget(
        new QLabel(tr("Conflicts — resolve before committing"), conflictedGroup_));
    conflictedList_ = new QListWidget(conflictedGroup_);
    conflictedList_->setMaximumHeight(120);
    conflictedList_->setAccessibleName(tr("Conflicted files"));
    conflictedLayout->addWidget(conflictedList_);
    conflictedGroup_->setVisible(false);
    leftLayout->addWidget(conflictedGroup_);

    leftLayout->addWidget(new QLabel(tr("Staged Changes"), leftWidget));
    stagedList_ = new QListWidget(leftWidget);
    stagedList_->setSelectionMode(QAbstractItemView::SingleSelection);
    stagedList_->setAccessibleName(tr("Staged changes"));
    leftLayout->addWidget(stagedList_, 1);
    unstageAllButton_ = new QPushButton(tr("Unstage All"), leftWidget);
    leftLayout->addWidget(unstageAllButton_);

    leftLayout->addWidget(new QLabel(tr("Changes"), leftWidget));
    unstagedList_ = new QListWidget(leftWidget);
    unstagedList_->setSelectionMode(QAbstractItemView::SingleSelection);
    unstagedList_->setContextMenuPolicy(Qt::CustomContextMenu);
    unstagedList_->setAccessibleName(tr("Unstaged changes"));
    leftLayout->addWidget(unstagedList_, 1);
    stageAllButton_ = new QPushButton(tr("Stage All"), leftWidget);
    leftLayout->addWidget(stageAllButton_);

    messageEdit_ = new QPlainTextEdit(leftWidget);
    messageEdit_->setPlaceholderText(tr("Commit message"));
    messageEdit_->setMaximumHeight(100);
    messageEdit_->setAccessibleName(tr("Commit message"));
    leftLayout->addWidget(messageEdit_);

    auto* commitRow = new QHBoxLayout();
    amendCheck_ = new QCheckBox(tr("Amend"), leftWidget);
    commitButton_ = new QPushButton(tr("Commit"), leftWidget);
    commitButton_->setEnabled(false);
    commitRow->addWidget(amendCheck_);
    commitRow->addStretch(1);
    commitRow->addWidget(commitButton_);
    leftLayout->addLayout(commitRow);

    splitter->addWidget(leftWidget);

    auto* diffPane = new QWidget(splitter);
    auto* diffPaneLayout = new QVBoxLayout(diffPane);
    diffPaneLayout->setContentsMargins(0, 0, 0, 0);

    sideBySideToggle_ = new QCheckBox(tr("Side by side"), diffPane);
    diffPaneLayout->addWidget(sideBySideToggle_, 0, Qt::AlignRight);

    diffStack_ = new QStackedWidget(diffPane);
    // Hunk- and line-level staging live on this instance's context menu; see
    // DiffView::setStagingEnabled. The side-by-side pane is read-only -- it
    // has no equivalent context menu, so staging always happens from the
    // unified view.
    diffView_ = new DiffView(diffStack_);
    diffView_->setStagingEnabled(true);
    sideBySideView_ = new SideBySideDiffView(diffStack_);
    diffStack_->addWidget(diffView_);
    diffStack_->addWidget(sideBySideView_);
    diffPaneLayout->addWidget(diffStack_, 1);

    splitter->addWidget(diffPane);
    splitter->setStretchFactor(0, 2);
    splitter->setStretchFactor(1, 3);

    outerLayout->addWidget(splitter, 1);

    connect(stagedList_,
            &QListWidget::itemSelectionChanged,
            this,
            &WorkingCopyView::onStagedSelectionChanged);
    connect(unstagedList_,
            &QListWidget::itemSelectionChanged,
            this,
            &WorkingCopyView::onUnstagedSelectionChanged);
    connect(
        stagedList_, &QListWidget::itemActivated, this, &WorkingCopyView::onStagedItemActivated);
    connect(unstagedList_,
            &QListWidget::itemActivated,
            this,
            &WorkingCopyView::onUnstagedItemActivated);
    connect(conflictedList_,
            &QListWidget::itemActivated,
            this,
            &WorkingCopyView::onConflictedItemActivated);
    connect(
        unstagedList_, &QListWidget::customContextMenuRequested, this, [this](const QPoint& pos) {
            auto* item = unstagedList_->itemAt(pos);
            if (item == nullptr || session_ == nullptr) {
                return;
            }
            // `git restore` has nothing to discard an untracked file back
            // to -- there is no HEAD/index content for it -- so it is left
            // out of the menu rather than offering an action that would
            // just fail.
            if (item->data(kUntrackedRole).toBool()) {
                return;
            }
            const std::string path = item->data(Qt::UserRole).toString().toStdString();

            QMenu menu(unstagedList_);
            QAction* discardAction = menu.addAction(tr("Discard Changes…"));
            if (menu.exec(unstagedList_->viewport()->mapToGlobal(pos)) != discardAction) {
                return;
            }
            const auto confirmed =
                QMessageBox::warning(this,
                                     tr("Discard changes?"),
                                     tr("This permanently discards your uncommitted changes "
                                        "to \"%1\".")
                                         .arg(QString::fromStdString(path)),
                                     QMessageBox::Discard | QMessageBox::Cancel,
                                     QMessageBox::Cancel);
            if (confirmed != QMessageBox::Discard) {
                return;
            }
            RestoreRequest request;
            request.paths = {path};
            request.staged = false;
            session_->restorePaths(request);
        });
    connect(sideBySideToggle_, &QCheckBox::toggled, this, [this](bool sideBySide) {
        diffStack_->setCurrentWidget(sideBySide ? static_cast<QWidget*>(sideBySideView_)
                                                : static_cast<QWidget*>(diffView_));
    });
    connect(stageAllButton_, &QPushButton::clicked, this, &WorkingCopyView::onStageAllClicked);
    connect(unstageAllButton_, &QPushButton::clicked, this, &WorkingCopyView::onUnstageAllClicked);
    connect(commitButton_, &QPushButton::clicked, this, &WorkingCopyView::onCommitClicked);
    connect(amendCheck_, &QCheckBox::toggled, this, [this](bool amend) {
        messageEdit_->setPlaceholderText(amend ? tr("Leave empty to keep the previous message")
                                               : tr("Commit message"));
    });
    connect(
        diffView_, &DiffView::applyPatchRequested, this, &WorkingCopyView::onApplyPatchRequested);
}

void WorkingCopyView::refreshTheme() {
    diffView_->refreshTheme();
    sideBySideView_->refreshTheme();
}

void WorkingCopyView::setSession(RepositorySession* session) {
    if (session_ != nullptr) {
        disconnect(session_, nullptr, this, nullptr);
    }
    session_ = session;
    if (session_ != nullptr) {
        connect(session_,
                &RepositorySession::workingCopyStatusUpdated,
                this,
                &WorkingCopyView::onWorkingCopyStatusUpdated);
        connect(session_,
                &RepositorySession::workingCopyDiffReady,
                this,
                &WorkingCopyView::onWorkingCopyDiffReady);
        connect(session_,
                &RepositorySession::workingCopyOperationFinished,
                this,
                &WorkingCopyView::onWorkingCopyOperationFinished);
        session_->refreshWorkingCopyStatus();
    } else {
        diffView_->clearDiff();
        sideBySideView_->clearDiff();
        messageEdit_->clear();
        rebuildLists();
    }
}

std::optional<WorkingCopyView::Selection> WorkingCopyView::currentSelection() const {
    if (const auto items = stagedList_->selectedItems(); !items.isEmpty()) {
        return Selection{items.first()->data(Qt::UserRole).toString().toStdString(), true};
    }
    if (const auto items = unstagedList_->selectedItems(); !items.isEmpty()) {
        return Selection{items.first()->data(Qt::UserRole).toString().toStdString(), false};
    }
    return std::nullopt;
}

void WorkingCopyView::rebuildLists() {
    // Captured before clearing, so the file the user is looking at can be
    // re-selected afterwards: a hunk staged from this file must not blank the
    // diff pane out from under them.
    const auto previous = currentSelection();

    stagedList_->blockSignals(true);
    unstagedList_->blockSignals(true);
    conflictedList_->blockSignals(true);
    stagedList_->clear();
    unstagedList_->clear();
    conflictedList_->clear();

    const WorkingCopyStatusPtr status = session_ ? session_->workingCopyStatus() : nullptr;
    if (status) {
        for (const WorkingCopyEntry* entry : status->conflicted()) {
            addEntry(conflictedList_, *entry, QString());
        }
        for (const WorkingCopyEntry* entry : status->staged()) {
            addEntry(stagedList_, *entry, QString());
        }
        for (const WorkingCopyEntry* entry : status->unstaged()) {
            addEntry(unstagedList_, *entry, QString());
        }
        for (const WorkingCopyEntry* entry : status->untracked()) {
            addEntry(unstagedList_, *entry, tr("  (untracked)"), true);
        }
    }

    stagedList_->blockSignals(false);
    unstagedList_->blockSignals(false);
    conflictedList_->blockSignals(false);

    bool reselected = false;
    if (previous) {
        for (QListWidget* list : {stagedList_, unstagedList_}) {
            for (int row = 0; row < list->count(); ++row) {
                if (list->item(row)->data(Qt::UserRole).toString().toStdString() ==
                    previous->path) {
                    list->setCurrentItem(list->item(row));
                    reselected = true;
                    break;
                }
            }
            if (reselected) {
                break;
            }
        }
    }
    if (previous && !reselected) {
        diffView_->clearDiff();
        sideBySideView_->clearDiff();
    }

    const bool hasConflicts = conflictedList_->count() > 0;
    conflictedGroup_->setVisible(hasConflicts);

    if (!status) {
        summaryLabel_->setText(tr("No repository open"));
    } else if (status->isClean()) {
        summaryLabel_->setText(tr("No changes"));
    } else {
        summaryLabel_->setText(
            tr("%1 staged, %2 to review").arg(stagedList_->count()).arg(unstagedList_->count()));
    }

    commitButton_->setEnabled(stagedList_->count() > 0 && !hasConflicts);
    stageAllButton_->setEnabled(unstagedList_->count() > 0);
    unstageAllButton_->setEnabled(stagedList_->count() > 0);
}

void WorkingCopyView::refreshSelectedDiff() {
    if (session_ == nullptr) {
        return;
    }
    const auto selection = currentSelection();
    if (!selection) {
        diffView_->clearDiff();
        sideBySideView_->clearDiff();
        return;
    }
    diffView_->showMessage(tr("Loading changes…"));
    sideBySideView_->showMessage(tr("Loading changes…"));
    session_->requestWorkingCopyDiff(selection->path, selection->staged);
}

void WorkingCopyView::onWorkingCopyStatusUpdated() {
    rebuildLists();
}

void WorkingCopyView::onWorkingCopyDiffReady(QString path,
                                             bool staged,
                                             std::shared_ptr<const ParsedDiff> diff) {
    const auto selection = currentSelection();
    if (!selection || QString::fromStdString(selection->path) != path ||
        selection->staged != staged) {
        // The user moved on before this arrived.
        return;
    }
    diffView_->setShowingStagedDiff(staged);
    diffView_->showDiff(diff);
    sideBySideView_->showDiff(std::move(diff));
}

void WorkingCopyView::onWorkingCopyOperationFinished(const OperationOutcome& outcome) {
    if (outcome.succeeded) {
        emit statusMessage(QString::fromStdString(outcome.summary));
        // CommitOperation::describe() is exactly "Commit" or "Amend commit";
        // no other working-copy operation's summary starts that way.
        if (outcome.summary.rfind("Commit", 0) == 0 || outcome.summary.rfind("Amend", 0) == 0) {
            messageEdit_->clear();
            amendCheck_->setChecked(false);
        }
        return;
    }
    if (outcome.error) {
        emit errorOccurred(QString::fromStdString(outcome.summary), *outcome.error);
    }
}

void WorkingCopyView::onStagedSelectionChanged() {
    if (stagedList_->selectedItems().isEmpty()) {
        return;
    }
    unstagedList_->blockSignals(true);
    unstagedList_->clearSelection();
    unstagedList_->blockSignals(false);
    refreshSelectedDiff();
}

void WorkingCopyView::onUnstagedSelectionChanged() {
    if (unstagedList_->selectedItems().isEmpty()) {
        return;
    }
    stagedList_->blockSignals(true);
    stagedList_->clearSelection();
    stagedList_->blockSignals(false);
    refreshSelectedDiff();
}

void WorkingCopyView::onStagedItemActivated(QListWidgetItem* item) {
    if (session_ == nullptr || item == nullptr) {
        return;
    }
    session_->unstageFiles({item->data(Qt::UserRole).toString().toStdString()});
}

void WorkingCopyView::onUnstagedItemActivated(QListWidgetItem* item) {
    if (session_ == nullptr || item == nullptr) {
        return;
    }
    session_->stageFiles({item->data(Qt::UserRole).toString().toStdString()});
}

void WorkingCopyView::onConflictedItemActivated(QListWidgetItem* item) {
    if (session_ == nullptr || item == nullptr) {
        return;
    }
    const std::string path = item->data(Qt::UserRole).toString().toStdString();
    const WorkingCopyStatusPtr status = session_->workingCopyStatus();
    if (!status) {
        return;
    }
    for (const WorkingCopyEntry* entry : status->conflicted()) {
        if (entry->path == path) {
            openConflictResolutionDialog(*entry);
            return;
        }
    }
}

void WorkingCopyView::openConflictResolutionDialog(const WorkingCopyEntry& entry) {
    if (session_ == nullptr) {
        return;
    }

    QDialog dialog(this);
    dialog.setWindowTitle(tr("Resolve conflict — %1").arg(QString::fromStdString(entry.path)));
    auto* layout = new QVBoxLayout(&dialog);

    QString kindText;
    switch (entry.conflict) {
        case ConflictKind::BothAdded:
            kindText = tr("Both sides added this file.");
            break;
        case ConflictKind::BothModified:
            kindText = tr("Both sides modified this file.");
            break;
        case ConflictKind::BothDeleted:
            kindText = tr("Both sides deleted this file.");
            break;
        case ConflictKind::AddedByUs:
            kindText = tr("You added this file; the other side did not touch it.");
            break;
        case ConflictKind::DeletedByUs:
            kindText = tr("You deleted this file; the other side modified it.");
            break;
        case ConflictKind::AddedByThem:
            kindText = tr("The other side added this file; you did not touch it.");
            break;
        case ConflictKind::DeletedByThem:
            kindText = tr("The other side deleted this file; you modified it.");
            break;
        case ConflictKind::None:
            break;
    }
    if (!kindText.isEmpty()) {
        layout->addWidget(new QLabel(kindText, &dialog));
    }

    auto* panesLayout = new QHBoxLayout();
    auto makePane = [&](const QString& title) {
        auto* container = new QWidget(&dialog);
        auto* paneLayout = new QVBoxLayout(container);
        paneLayout->setContentsMargins(0, 0, 0, 0);
        paneLayout->addWidget(new QLabel(title, container));
        auto* edit = new QPlainTextEdit(container);
        edit->setReadOnly(true);
        edit->setLineWrapMode(QPlainTextEdit::NoWrap);
        edit->setPlainText(tr("Loading…"));
        paneLayout->addWidget(edit, 1);
        panesLayout->addWidget(container);
        return edit;
    };
    QPlainTextEdit* ancestorEdit = makePane(tr("Common ancestor"));
    QPlainTextEdit* oursEdit = makePane(tr("Mine (ours)"));
    QPlainTextEdit* theirsEdit = makePane(tr("Theirs"));
    if (entry.ancestorBlob.empty()) {
        ancestorEdit->setPlainText(tr("(no common ancestor)"));
    }
    if (entry.oursBlob.empty()) {
        oursEdit->setPlainText(tr("(deleted on this side)"));
    }
    if (entry.theirsBlob.empty()) {
        theirsEdit->setPlainText(tr("(deleted on the other side)"));
    }
    layout->addLayout(panesLayout, 1);

    // Scoped to the dialog's lifetime via the context object: if the request's
    // reply arrives after the dialog has already closed, Qt drops the
    // connection rather than calling back into destroyed widgets.
    const QString path = QString::fromStdString(entry.path);
    connect(session_,
            &RepositorySession::conflictSidesReady,
            &dialog,
            [path, ancestorEdit, oursEdit, theirsEdit](
                QString readyPath, QString ancestor, QString ours, QString theirs) {
                if (readyPath != path) {
                    return;
                }
                ancestorEdit->setPlainText(ancestor);
                oursEdit->setPlainText(ours);
                theirsEdit->setPlainText(theirs);
            });
    session_->requestConflictSides(
        entry.path, entry.ancestorBlob, entry.oursBlob, entry.theirsBlob);

    auto* buttonRow = new QHBoxLayout();
    auto* takeOursButton = new QPushButton(tr("Take Mine"), &dialog);
    auto* takeTheirsButton = new QPushButton(tr("Take Theirs"), &dialog);
    auto* markResolvedButton = new QPushButton(tr("Mark Resolved"), &dialog);
    auto* cancelButton = new QPushButton(tr("Cancel"), &dialog);
    buttonRow->addWidget(takeOursButton);
    buttonRow->addWidget(takeTheirsButton);
    buttonRow->addWidget(markResolvedButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(cancelButton);
    layout->addLayout(buttonRow);

    connect(takeOursButton, &QPushButton::clicked, &dialog, [&dialog] { dialog.done(1); });
    connect(takeTheirsButton, &QPushButton::clicked, &dialog, [&dialog] { dialog.done(2); });
    connect(markResolvedButton, &QPushButton::clicked, &dialog, [&dialog] { dialog.done(3); });
    connect(cancelButton, &QPushButton::clicked, &dialog, [&dialog] { dialog.done(0); });

    dialog.resize(720, 420);
    const int result = dialog.exec();
    if (result == 0 || session_ == nullptr) {
        return;
    }

    ResolveConflictRequest request;
    request.path = entry.path;
    request.oursBlobMissing = entry.oursBlob.empty();
    request.theirsBlobMissing = entry.theirsBlob.empty();
    switch (result) {
        case 1:
            request.resolution = ConflictResolution::TakeOurs;
            break;
        case 2:
            request.resolution = ConflictResolution::TakeTheirs;
            break;
        default:
            request.resolution = ConflictResolution::MarkResolved;
            break;
    }
    session_->resolveConflict(request);
}

void WorkingCopyView::onStageAllClicked() {
    if (session_ == nullptr) {
        return;
    }
    std::vector<std::string> paths;
    paths.reserve(static_cast<std::size_t>(unstagedList_->count()));
    for (int row = 0; row < unstagedList_->count(); ++row) {
        paths.push_back(unstagedList_->item(row)->data(Qt::UserRole).toString().toStdString());
    }
    if (!paths.empty()) {
        session_->stageFiles(std::move(paths));
    }
}

void WorkingCopyView::onUnstageAllClicked() {
    if (session_ == nullptr) {
        return;
    }
    std::vector<std::string> paths;
    paths.reserve(static_cast<std::size_t>(stagedList_->count()));
    for (int row = 0; row < stagedList_->count(); ++row) {
        paths.push_back(stagedList_->item(row)->data(Qt::UserRole).toString().toStdString());
    }
    if (!paths.empty()) {
        session_->unstageFiles(std::move(paths));
    }
}

void WorkingCopyView::onCommitClicked() {
    if (session_ == nullptr) {
        return;
    }
    CommitRequest request;
    request.message = messageEdit_->toPlainText().toStdString();
    request.amend = amendCheck_->isChecked();
    session_->commitChanges(request);
}

void WorkingCopyView::onApplyPatchRequested(QString patch, bool reverse) {
    if (session_ == nullptr) {
        return;
    }
    session_->applyPatch(patch.toStdString(), reverse);
}

}  // namespace gbm
