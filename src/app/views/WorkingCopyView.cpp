#include "app/views/WorkingCopyView.h"

#include "app/bridge/RepositorySession.h"
#include "core/git/ops/CommitOps.h"

#include <QCheckBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSplitter>
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

QListWidgetItem* addEntry(QListWidget* list, const WorkingCopyEntry& entry, const QString& suffix) {
    auto* item = new QListWidgetItem(pathLabel(entry) + suffix, list);
    item->setData(Qt::UserRole, QString::fromStdString(entry.path));
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
    conflictedLayout->addWidget(conflictedList_);
    conflictedGroup_->setVisible(false);
    leftLayout->addWidget(conflictedGroup_);

    leftLayout->addWidget(new QLabel(tr("Staged Changes"), leftWidget));
    stagedList_ = new QListWidget(leftWidget);
    stagedList_->setSelectionMode(QAbstractItemView::SingleSelection);
    leftLayout->addWidget(stagedList_, 1);
    unstageAllButton_ = new QPushButton(tr("Unstage All"), leftWidget);
    leftLayout->addWidget(unstageAllButton_);

    leftLayout->addWidget(new QLabel(tr("Changes"), leftWidget));
    unstagedList_ = new QListWidget(leftWidget);
    unstagedList_->setSelectionMode(QAbstractItemView::SingleSelection);
    leftLayout->addWidget(unstagedList_, 1);
    stageAllButton_ = new QPushButton(tr("Stage All"), leftWidget);
    leftLayout->addWidget(stageAllButton_);

    messageEdit_ = new QPlainTextEdit(leftWidget);
    messageEdit_->setPlaceholderText(tr("Commit message"));
    messageEdit_->setMaximumHeight(100);
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

    // Hunk- and line-level staging live on this instance's context menu; see
    // DiffView::setStagingEnabled.
    diffView_ = new DiffView(splitter);
    diffView_->setStagingEnabled(true);
    splitter->addWidget(diffView_);
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
            addEntry(unstagedList_, *entry, tr("  (untracked)"));
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
        return;
    }
    diffView_->showMessage(tr("Loading changes…"));
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
    diffView_->showDiff(std::move(diff));
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
