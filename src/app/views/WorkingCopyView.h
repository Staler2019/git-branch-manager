#pragma once

#include "app/views/DiffView.h"
#include "core/base/Error.h"
#include "core/git/OperationRunner.h"

#include <QWidget>

#include <memory>
#include <optional>
#include <string>

class QCheckBox;
class QLabel;
class QListWidget;
class QListWidgetItem;
class QPlainTextEdit;
class QPushButton;

namespace gbm {

class RepositorySession;

/// The working-copy panel: status, stage/unstage by file, hunk and line, and
/// commit/amend -- M1's working-copy slice wired into one view. Hunk- and
/// line-level staging live in the embedded DiffView's context menu; this
/// class owns whole-file staging, the two status lists, and the commit box.
class WorkingCopyView : public QWidget {
    Q_OBJECT

public:
    explicit WorkingCopyView(QWidget* parent = nullptr);

    /// Attaches to a repository, or detaches (and clears everything) when
    /// `session` is null.
    void setSession(RepositorySession* session);

signals:
    void statusMessage(QString message);
    void errorOccurred(QString summary, GitError error);

private slots:
    void onWorkingCopyStatusUpdated();
    void onWorkingCopyDiffReady(QString path, bool staged, std::shared_ptr<const ParsedDiff> diff);
    void onWorkingCopyOperationFinished(const OperationOutcome& outcome);
    void onStagedSelectionChanged();
    void onUnstagedSelectionChanged();
    void onStagedItemActivated(QListWidgetItem* item);
    void onUnstagedItemActivated(QListWidgetItem* item);
    void onStageAllClicked();
    void onUnstageAllClicked();
    void onCommitClicked();
    void onApplyPatchRequested(QString patch, bool reverse);

private:
    void buildUi();
    void rebuildLists();
    void refreshSelectedDiff();

    struct Selection {
        std::string path;
        bool staged = false;
    };

    /// The path + side currently selected across the two lists (at most one
    /// list ever has a selection at a time -- see onStaged/UnstagedSelectionChanged).
    std::optional<Selection> currentSelection() const;

    RepositorySession* session_ = nullptr;

    QLabel* summaryLabel_ = nullptr;
    QWidget* conflictedGroup_ = nullptr;
    QListWidget* conflictedList_ = nullptr;
    QListWidget* stagedList_ = nullptr;
    QListWidget* unstagedList_ = nullptr;
    QPushButton* stageAllButton_ = nullptr;
    QPushButton* unstageAllButton_ = nullptr;
    DiffView* diffView_ = nullptr;
    QPlainTextEdit* messageEdit_ = nullptr;
    QCheckBox* amendCheck_ = nullptr;
    QPushButton* commitButton_ = nullptr;
};

}  // namespace gbm
