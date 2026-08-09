#pragma once

#include "core/git/ConflictBatch.h"
#include "core/git/WorkingCopyStatus.h"

#include <QWidget>

#include <optional>
#include <set>
#include <string>
#include <vector>

class QCheckBox;
class QCloseEvent;
class QLabel;
class QListWidget;
class QListWidgetItem;
class QPushButton;
class QSplitter;

namespace gbm {

class ConflictResolvePanel;
class RepositorySession;

/// Design B1: which rail row to auto-select once `resolvedIndex` has just
/// transitioned from Unresolved to Resolved -- mirrors
/// ConflictResolvePanel::resolveRegion()'s own forward-then-wrap-but-never-
/// back-onto-self search (same UX goal: work through a batch in a straight
/// line without landing back on the file just finished). `entries` is
/// whatever ConflictBatch::entries() returns right now; nullopt means every
/// other entry is already resolved, i.e. nothing left to jump to. A free
/// function so it's directly unit-testable with a plain vector, no window
/// or ConflictBatch construction required -- same reasoning as
/// middleBufferHasUnsavedEdits()/summarizeConflictSideTraits() in
/// ConflictResolvePanel.h.
std::optional<int> nextUnresolvedRailIndex(const std::vector<ConflictBatchEntry>& entries,
                                           int resolvedIndex);

/// Design B1 + B2's app-side wiring: a standalone window listing every
/// conflicted file in the current merge/rebase/cherry-pick (left rail,
/// backed by a ConflictBatch so resolved files stay visible with a
/// checkmark instead of vanishing) and a single reused ConflictResolvePanel
/// (right side) for whichever file is currently selected.
///
/// This is the wider view the modal QDialog in
/// WorkingCopyView::openConflictResolutionDialog() (720x420, no file
/// picker, no progress memory) could never give -- see the plan's Context
/// section.
///
/// Batch memory here is in-memory only, scoped to this window's lifetime --
/// QSettings persistence across app restarts and a real operationFingerprint
/// (RepoState-derived) are a separate commit (C12b) so that persistence
/// bug surface doesn't ride along with "does the window work at all".
///
/// C13: modal with three explicit exits. This stays a plain QWidget rather
/// than becoming a QDialog -- setWindowModality(Qt::ApplicationModal) works
/// on any top-level QWidget, and switching to QDialog::exec() would collide
/// with WA_DeleteOnClose (the dialog would delete itself out from under
/// exec()'s own stack frame on close). Three buttons at the bottom map to
/// the plan's three exits (儲存目前進度/全部套用並完成/取消); Esc and the
/// window's own close button (titlebar X / Alt+F4 / Cmd+W) all resolve to
/// the same Cancel path via closeEvent() -- see pendingExit_'s own comment
/// for how that single guard covers every exit without prompting twice.
/// Abort (git merge --abort) is deliberately never offered here -- it is a
/// repo-level destructive operation, not a per-file one, and stays on the
/// main window's banner only (must_not_do).
///
/// A note on what "unsaved" means here: ConflictResolvePanel writes each
/// file to the working tree and index the moment its own Save is pressed
/// (see submitResolution()) -- by the time a file shows resolved in the
/// rail, it is already on disk. So 儲存目前進度/全部套用並完成 have nothing
/// to flush beyond closing (progress is already persisted via
/// ConflictBatchStore on every refreshBatch()), and 取消's confirmation is
/// scoped to *only* the currently open file's not-yet-submitted choices --
/// see ConflictResolvePanel::hasUnsavedProgress(). Previously saved files in
/// this batch are never at risk from Cancel.
class ConflictResolveWindow : public QWidget {
    Q_OBJECT

public:
    explicit ConflictResolveWindow(QWidget* parent = nullptr);

    /// The only production construction path: builds the window, wires it
    /// to `session`'s workingCopyStatusUpdated() signal, does the first
    /// refreshBatch() from the session's current status, selects
    /// `initialPath` if it's conflicted, and show()s it. ApplicationModal
    /// (see the class comment) means the main window is blocked for the
    /// duration, so there is no session-swap-while-open hazard to guard
    /// against: the parent cannot switch repos while this is up. Takes a
    /// QWidget* rather than MainWindow* so this header never needs to
    /// include MainWindow.h.
    ///
    /// Parented to `parent` and WA_DeleteOnClose, so it is destroyed once
    /// the user leaves through one of the three exits. The returned pointer
    /// is only useful before that -- callers must not hold onto it past
    /// their own return, same as any WA_DeleteOnClose widget.
    static ConflictResolveWindow* openFor(QWidget* parent,
                                          RepositorySession* session,
                                          const QString& initialPath);

    /// Merges `conflicted` into the in-memory ConflictBatch and re-renders
    /// the rail. Exposed (not just reachable via the session signal) so
    /// tests can drive it directly without a live RepositorySession -- the
    /// same reason ConflictUiTest.cpp never constructs one for
    /// ConflictResolvePanel either.
    ///
    /// Auto-advance (Design B1: "留原位、進度 1/3、自動選下一個") is decided
    /// here, not by any external hint: whichever entry is currently
    /// selected is compared before/after the merge, and only if *that one*
    /// just flipped Unresolved -> Resolved does the selection jump, via
    /// nextUnresolvedRailIndex(). A different file resolved out from under
    /// the user (an external `git add` on some other path, say) must not
    /// yank focus away from what they're actively working on.
    void refreshBatch(const std::vector<const WorkingCopyEntry*>& conflicted);

protected:
    /// The single guard every exit funnels through -- see pendingExit_'s own
    /// comment for why this, rather than each button, is what decides
    /// whether to confirm and what to persist. Also persists window geometry
    /// (`window/conflictResolveWindow/geometry`) -- the first geometry
    /// persistence anywhere in this app (see the plan's own note that
    /// src/app has none today).
    void closeEvent(QCloseEvent* event) override;

private:
    /// Which exit is in flight when closeEvent() runs -- set by a button's
    /// click handler just before it calls close(), read (and reset) by
    /// closeEvent() itself. Esc and the window's own close affordance never
    /// go through a button, so they reach closeEvent() with this still None;
    /// treating that the same as Cancel is exactly "Esc 與視窗關閉鈕都對應
    /// 「取消」" from the plan. Routing every exit through this one enum
    /// rather than letting each button decide for itself is what keeps a
    /// button's own confirm-then-close from being asked again a second time
    /// once closeEvent() runs -- there is exactly one place that ever shows
    /// the confirmation dialog.
    enum class PendingExit { None, SaveProgress, FinishAll, Cancel };
    PendingExit pendingExit_ = PendingExit::None;

    void rebuildRailRows();
    void selectEntryIndex(int index);
    void onPanelResolutionSubmitted();
    void onSessionWorkingCopyStatusUpdated();
    void saveSplitterSizes();
    void restoreSplitterSizes();
    /// Design B1's exit button enablement: 儲存目前進度 once at least one
    /// file is resolved, 全部套用並完成 only once the whole batch is.
    void updateExitButtonsEnabled();
    /// True if it's fine to close right now: either the currently open file
    /// has nothing unsaved, or the user just confirmed discarding it via a
    /// QMessageBox. See the class comment on why only the *currently open*
    /// file is ever at risk.
    bool confirmDiscardCurrentFileProgressIfAny();

    RepositorySession* session_ = nullptr;
    ConflictBatch conflictBatch_ = ConflictBatch::forOperation("");
    /// Kept alive so the WorkingCopyEntry pointers conflicted() handed back
    /// stay valid between refreshBatch() calls -- WorkingCopyStatusPtr is a
    /// shared_ptr<const WorkingCopyStatus> (see WorkingCopyStatus.h), so
    /// holding this is what keeps them from dangling once the session moves
    /// on to a newer snapshot.
    WorkingCopyStatusPtr currentStatus_;
    /// Index into conflictBatch_.entries() for whichever row is currently
    /// loaded into panel_ -- -1 before the rail has ever been populated.
    int currentEntryIndex_ = -1;
    /// Paths whose resolution was submitted through *this window's* panel_,
    /// as opposed to becoming Resolved because of an external `git add` --
    /// Design B2's three rail states need this distinction and
    /// ConflictBatch itself deliberately doesn't track it (see its own doc
    /// comment: merge() can't tell the two apart and doesn't need to for
    /// the batch's own bookkeeping). Purely a rail-presentation concern, so
    /// it lives here instead.
    std::set<std::string> resolvedByThisWindow_;

    QListWidget* railList_ = nullptr;
    QCheckBox* hideResolvedCheckbox_ = nullptr;
    QLabel* progressLabel_ = nullptr;
    QSplitter* splitter_ = nullptr;
    ConflictResolvePanel* panel_ = nullptr;

    /// Design B1's three explicit exits. Deliberately no Abort button here
    /// -- see the class comment's must_not_do.
    QPushButton* saveProgressButton_ = nullptr;
    QPushButton* finishAllButton_ = nullptr;
    QPushButton* cancelButton_ = nullptr;
};

}  // namespace gbm
