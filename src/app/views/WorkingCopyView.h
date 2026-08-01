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
class QStackedWidget;

namespace gbm {

class RepositorySession;
class SideBySideDiffView;
struct WorkingCopyEntry;

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

    /// Re-renders the embedded unified and side-by-side diff views so an
    /// already-displayed diff picks up the theme most recently passed to
    /// `ThemeManager::apply()`.
    void refreshTheme();

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
    void onConflictedItemActivated(QListWidgetItem* item);
    void onStageAllClicked();
    void onUnstageAllClicked();
    void onCommitClicked();
    void onApplyPatchRequested(QString patch, bool reverse);

private:
    void buildUi();
    void rebuildLists();
    void refreshSelectedDiff();
    /// Shows the three stages plus Take Mine/Take Theirs/Mark Resolved, and
    /// submits whichever the user picks. Blocks (modally) until closed, same
    /// as onManageBaseFolders in MainWindow.
    void openConflictResolutionDialog(const WorkingCopyEntry& entry);

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
    QStackedWidget* diffStack_ = nullptr;
    DiffView* diffView_ = nullptr;
    SideBySideDiffView* sideBySideView_ = nullptr;
    QCheckBox* sideBySideToggle_ = nullptr;
    QPlainTextEdit* messageEdit_ = nullptr;
    QCheckBox* amendCheck_ = nullptr;
    QPushButton* commitButton_ = nullptr;
};

}  // namespace gbm
