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
/// section. Non-modal in this commit: it opens via show(), not exec(), so
/// the main window stays interactive. Design B1's three explicit exits and
/// ApplicationModal wiring land in a later commit (C13) as an independently
/// revertable decision -- see openFor()'s own comment.
///
/// Batch memory here is in-memory only, scoped to this window's lifetime --
/// QSettings persistence across app restarts and a real operationFingerprint
/// (RepoState-derived) are a separate commit (C12b) so that persistence
/// bug surface doesn't ride along with "does the window work at all".
class ConflictResolveWindow : public QWidget {
    Q_OBJECT

public:
    explicit ConflictResolveWindow(QWidget* parent = nullptr);

    /// The only production construction path: builds the window, wires it
    /// to `session`'s workingCopyStatusUpdated() signal, does the first
    /// refreshBatch() from the session's current status, selects
    /// `initialPath` if it's conflicted, and show()s it (non-modal -- see
    /// the class comment). Takes a QWidget* rather than MainWindow* so this
    /// header never needs to include MainWindow.h.
    ///
    /// Parented to `parent` and WA_DeleteOnClose, so it is destroyed either
    /// when the user closes it or when `parent` (and therefore the session
    /// it borrows) goes away -- there is no session-swap-while-open hazard
    /// to guard against yet because nothing production-side calls this
    /// until C16 wires up the banner entry point, and this window does not
    /// yet outlive a single repo session by design.
    static ConflictResolveWindow* openFor(QWidget* parent, RepositorySession* session,
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
    /// Persists window geometry (`window/conflictResolveWindow/geometry`) --
    /// the first geometry persistence anywhere in this app (see the plan's
    /// own note that src/app has none today).
    void closeEvent(QCloseEvent* event) override;

private:
    void rebuildRailRows();
    void selectEntryIndex(int index);
    void onPanelResolutionSubmitted();
    void onSessionWorkingCopyStatusUpdated();
    void saveSplitterSizes();
    void restoreSplitterSizes();

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
};

}  // namespace gbm
