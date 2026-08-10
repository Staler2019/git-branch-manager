#pragma once

#include "app/views/DiffView.h"
#include "core/base/Error.h"
#include "core/git/OperationRunner.h"

#include <QPoint>
#include <QWidget>

#include <memory>
#include <optional>
#include <string>

class QCheckBox;
class QFrame;
class QLabel;
class QListWidget;
class QListWidgetItem;
class QPlainTextEdit;
class QPushButton;
class QStackedWidget;
class QTabWidget;

namespace gbm {

class FileContentView;
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

    /// "View diff" from either context menu: MainWindow switches to the Diff
    /// tab and requests this path's working-copy diff (staged or unstaged)
    /// for DiffPage -- the same RepositorySession::requestWorkingCopyDiff
    /// this view's own embedded pane already uses, just redirected.
    void viewFileDiffRequested(QString path, bool staged);
    /// Design C4: double-clicking a conflicted entry used to open a 720x420
    /// modal QDialog embedding a ConflictResolvePanel right here
    /// (openConflictResolutionDialog(), removed). MainWindow now owns the
    /// one path into ConflictResolveWindow (see bannerResolveButton_), so
    /// this just asks for the same window, pre-selecting `path`.
    void resolveConflictsRequested(QString path);

private slots:
    void onWorkingCopyStatusUpdated();
    void onWorkingCopyDiffReady(QString path, bool staged, std::shared_ptr<const ParsedDiff> diff);
    void onFileContentReady(QString path, QString revision, QString content, bool exists);
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
    /// Per-file checkbox toggled in the unstaged panel: checking stages the
    /// file, unchecking is a no-op (a file leaves the unstaged panel by being
    /// staged, not by unchecking its box back).
    void onUnstagedItemChanged(QListWidgetItem* item);
    /// Per-file checkbox toggled in the staged panel: unchecking unstages the
    /// file.
    void onStagedItemChanged(QListWidgetItem* item);
    /// Design C3: reply to requestPreparedCommitMessage(), fired once
    /// rebuildLists() notices every conflict just cleared. See
    /// autofilledMessage_'s own comment for the overwrite guard.
    void onPreparedCommitMessageReady(const QString& message);

private:
    void buildUi();

    /// Builds one of the two equal Unstaged/Staged panels: a bordered frame
    /// with a header (title + live count), a stacked widget switching between
    /// the file list and a centered "Drop files here" placeholder, and (for
    /// the caller to place) a whole-file stage/unstage-all button.
    struct FilePanel {
        QFrame* frame = nullptr;
        QListWidget* list = nullptr;
        QStackedWidget* stack = nullptr;
        QLabel* countLabel = nullptr;
    };

    FilePanel buildFilePanel(const QString& title);
    void rebuildLists();
    void refreshSelectedDiff();
    /// Builds and shows the unstaged-file context menu (Stage file / View
    /// diff / Open file / Copy path / Discard changes) for `entry`.
    void showUnstagedContextMenu(const WorkingCopyEntry& entry, const QPoint& globalPos);
    /// Builds and shows the staged-file context menu (Unstage file / View
    /// diff / Open file / Copy path) for `entry`.
    void showStagedContextMenu(const WorkingCopyEntry& entry, const QPoint& globalPos);

    struct Selection {
        std::string path;
        bool staged = false;
    };

    /// The path + side currently selected across the two lists (at most one
    /// list ever has a selection at a time -- see onStaged/UnstagedSelectionChanged).
    std::optional<Selection> currentSelection() const;

    RepositorySession* session_ = nullptr;

    QLabel* summaryLabel_ = nullptr;
    // Conflicted entries render inline as the first rows of unstagedList_
    // (see rebuildLists) rather than in a separate group box.
    QListWidget* stagedList_ = nullptr;
    QListWidget* unstagedList_ = nullptr;
    QStackedWidget* stagedStack_ = nullptr;
    QStackedWidget* unstagedStack_ = nullptr;
    QLabel* stagedCountLabel_ = nullptr;
    QLabel* unstagedCountLabel_ = nullptr;
    QPushButton* stageAllButton_ = nullptr;
    QPushButton* unstageAllButton_ = nullptr;
    /// Guards onUnstagedItemChanged/onStagedItemChanged against firing while
    /// rebuildLists() is (re)constructing items and setting their initial
    /// check state -- a stray stage/unstage call there would race the very
    /// status refresh that triggered the rebuild.
    bool rebuilding_ = false;

    /// One tab's worth of diff UI: the unified/side-by-side toggle this class
    /// already had, just duplicated per tab instead of shared across a single
    /// pane. `staged` is fixed at construction and is *not* inherited from
    /// whichever list the user last clicked -- the Working-changes tab is
    /// always the work-tree-vs-index diff and the Staged tab is always the
    /// index-vs-HEAD diff, regardless of which file-list row is selected.
    struct DiffTab {
        bool staged = false;
        QStackedWidget* stack = nullptr;
        DiffView* diffView = nullptr;
        SideBySideDiffView* sideBySideView = nullptr;
        QCheckBox* sideBySideToggle = nullptr;
    };

    DiffTab buildDiffTab(QWidget* parent, bool staged);
    /// Routes a workingCopyDiffReady reply to whichever DiffTab requested it.
    void showDiffInTab(DiffTab& tab, std::shared_ptr<const ParsedDiff> diff);
    void clearDiffTab(const DiffTab& tab);

    /// Design C4: placed directly in the splitter now -- no longer wrapped
    /// in a conflictStack_/conflictPanel_ pair that could take over this
    /// pane. Resolving conflicts is now exclusively ConflictResolveWindow's
    /// job (see resolveConflictsRequested()); this view only ever shows
    /// diffs.
    QTabWidget* diffTabs_ = nullptr;
    /// Design C3: whether the last rebuildLists() saw at least one
    /// conflicted file -- compared against the current call's status to
    /// detect the Unresolved -> none transition that triggers
    /// requestPreparedCommitMessage(). Reset in setSession() (both branches:
    /// a brand-new session has no history of its own to react to, and a
    /// leftover true from the previous session must not fire a spurious
    /// request against an unrelated repo that never had conflicts).
    bool hadConflictedFilesLastRefresh_ = false;
    /// Design C3's overwrite guard (must_not_do: "不得覆蓋使用者已經打好的
    /// commit message"): what onPreparedCommitMessageReady() last wrote into
    /// messageEdit_, if anything. A fill only happens when messageEdit_ is
    /// empty or still holds exactly this value -- once the user types
    /// something of their own, this stops matching and no future reply ever
    /// overwrites it again. Cleared everywhere messageEdit_ itself is
    /// cleared, so a fresh empty box after a commit/session-switch is
    /// fillable again rather than permanently "already autofilled".
    QString autofilledMessage_;
    FileContentView* originalView_ = nullptr;
    DiffTab workingTab_;
    DiffTab stagedTab_;
    QPlainTextEdit* messageEdit_ = nullptr;
    QCheckBox* amendCheck_ = nullptr;
    QPushButton* commitButton_ = nullptr;
};

}  // namespace gbm
