#pragma once

#include "app/views/ConflictTextEdit.h"
#include "core/git/ConflictMarkerParser.h"

#include <QWidget>

#include <optional>
#include <string>
#include <utility>
#include <vector>

class QCheckBox;
class QLabel;
class QPushButton;
class QSplitter;

namespace gbm {

class RepositorySession;
struct WorkingCopyEntry;

/// One conflicted path's resolution view: left = the current branch's side
/// (ours), middle = the editable resolved content (the actual working-tree
/// file, conflict markers and all), right = the merged-in branch's side
/// (theirs), plus an optional common-ancestor column (hidden by default --
/// see ancestorToggle_) placed leftmost. All four panes live in one
/// QSplitter so their widths persist across sessions. Wired to
/// RepositorySession::requestConflictSides/requestWorkingTreeContent/
/// resolveConflict. Extracted from
/// WorkingCopyView::openConflictResolutionDialog so the same widget can be
/// reused outside a modal QDialog.
class ConflictResolvePanel : public QWidget {
    Q_OBJECT

public:
    explicit ConflictResolvePanel(QWidget* parent = nullptr);

    /// Loads `entry` and starts the background reads of its three stages and
    /// its on-disk (editable) content via `session`.
    void showEntry(RepositorySession* session, const WorkingCopyEntry& entry);

signals:
    /// A resolution (take left / take right / save & mark resolved) has been
    /// submitted to the session.
    void resolutionSubmitted();
    /// The user cancelled without resolving.
    void cancelled();

private:
    void onConflictSidesReady(const QString& path,
                              const QString& ancestor,
                              const QString& ours,
                              const QString& theirs);
    void onWorkingTreeContentReady(const QString& path, const QString& content, bool editable);
    void submitResolution(int choice);

    /// Re-renders the ours/theirs panes (and their region row-span maps)
    /// from whichever source is authoritative right now: parsedMarkers_'s
    /// segments (see buildSidePaneText() in ConflictTextEdit.h) once
    /// regionCount > 0, or the raw blob text captured by
    /// onConflictSidesReady() otherwise. Called from the tail of *both*
    /// onConflictSidesReady() and onWorkingTreeContentReady() -- those are
    /// two independent RepositorySession replies with no ordering guarantee,
    /// so whichever lands second is what actually produces the correct,
    /// final render; the one that lands first produces a partial render
    /// that this then replaces.
    void refreshSidePanes();

    /// Renders the middle column's text for the current parsedMarkers_ +
    /// regionResolutions_: plain-text segments pass through verbatim, a
    /// resolved region's chosen lines are inlined, and an unresolved region
    /// becomes one placeholder line -- conflict marker text (<<<<<<< etc.)
    /// never appears in the result. Only meaningful when
    /// parsedMarkers_.regionCount > 0; see onWorkingTreeContentReady.
    /// When `regionRanges` is non-null it is filled with each region's
    /// [start, length) character range in the returned text, in region
    /// order -- see highlightCurrentRegion().
    QString buildMiddlePreviewText(std::vector<std::pair<int, int>>* regionRanges = nullptr) const;
    /// True once every parsed region has an explicit (non-Unresolved) choice.
    bool allRegionsResolved() const;
    /// Whether the Save button should be enabled: an editable file with no
    /// regions (whole-file path, unchanged from before per-region resolution
    /// existed) or one where every region has been resolved.
    bool canSave() const;
    /// Re-renders the middle column from the current regionResolutions_ --
    /// the live per-region preview (with a placeholder for any region still
    /// Unresolved) while unresolved regions remain, or the fully assembled,
    /// marker-free result (now editable, for final touch-ups) once every
    /// region has a choice. Also refreshes the strip and the highlight.
    void refreshMiddleFromResolutions();
    /// Sets `regionResolutions_[index]` to `resolution`, re-renders, and
    /// jumps to the next still-unresolved region if there is one, so working
    /// through a batch of conflicts is a straight line of clicks. Shared by
    /// Take Left/Take Right (plain Ours/Theirs, no custom lines), the
    /// line-picker dialog (Custom), and dragging a region onto the middle
    /// pane (plain Ours/Theirs, via ConflictTextEdit::regionDropped()).
    void resolveRegion(int index, ConflictRegionResolution resolution);
    /// Take-left/take-right applied to every region at once.
    void resolveAllRegions(ConflictRegionChoice choice);
    /// Moves currentRegionIndex_ by `delta`, clamped to the valid range.
    void navigateRegion(int delta);
    /// Reflects currentRegionIndex_ (position, resolved state, prev/next
    /// enablement) onto the strip widgets. No-op when regionCount == 0.
    void updateRegionStrip();
    /// Scrolls the middle column to and highlights the current region's
    /// rendered text, using the ranges buildMiddlePreviewText() recorded.
    /// Clears the highlight once every region is resolved (the ranges are
    /// then stale -- the buffer is the fully assembled text, not the
    /// per-region preview they were measured against).
    void highlightCurrentRegion();
    /// The Region segment backing `regionIndex` (0-based, region-only
    /// numbering, matching currentRegionIndex_/regionResolutions_) --
    /// parsedMarkers_.segments also holds Text segments interleaved in
    /// between, so this isn't a direct index. Returns nullptr if regionIndex
    /// is out of range.
    const ConflictSegment* regionSegment(int regionIndex) const;

    /// Design A2: a click on a single ours/theirs line toggles whether that
    /// line is part of a Custom resolution for its region -- `side`/
    /// `lineOffset` come from ConflictTextEdit::lineToggled(), `lineOffset`
    /// being 0-based from that region's first row on that side. Plain click
    /// toggles just that line; Shift+click extends from the last plain
    /// click in the same region+side (see lastLineClickAnchor_) to
    /// `lineOffset`, selecting the whole range. Unlike resolveRegion(), this
    /// never jumps to the next unresolved region -- the user is still
    /// working through this one line by line.
    void onRegionLineToggled(int regionIndex, ConflictSide side, int lineOffset, Qt::KeyboardModifiers modifiers);
    /// Lazily sizes and seeds customOursLineSelected_[regionIndex]/
    /// customTheirsLineSelected_[regionIndex] the first time a line in that
    /// region is clicked: all-false if the region is still Unresolved (or
    /// already Custom -- a fresh in-progress Custom selection isn't
    /// recoverable from customLines alone, since that would need matching
    /// each stored line back to a side+offset), or seeded to match
    /// segment.ours/theirs entirely selected if the region was already
    /// Ours/Theirs (e.g. via Take Left/Right or a drag) -- so the first
    /// click starts from what's already chosen rather than discarding it.
    /// A no-op on every later call for the same region.
    void ensureCustomLineSelectionSeeded(int regionIndex, const ConflictSegment& segment);
    /// Clears regionIndex's in-progress line-click selection and its
    /// gutter check marks on both edits -- called whenever something other
    /// than the click flow itself sets that region's resolution (Take Left/
    /// Right, Take All, or a drag), since any of those supersede whatever
    /// partial line selection was in progress and leaving it displayed
    /// would be stale.
    void resetCustomLineSelection(int regionIndex);

    RepositorySession* session_ = nullptr;
    std::string path_;
    bool ancestorBlobMissing_ = false;
    bool oursBlobMissing_ = false;
    bool theirsBlobMissing_ = false;
    /// True when the middle column's on-disk content had CRLF line endings,
    /// so a save can restore them -- QPlainTextEdit normalises everything it
    /// displays to bare `\n`, so this has to be captured before the content
    /// ever reaches the widget.
    bool middleContentHasCrlf_ = false;
    /// Mirrors whether the middle column is currently editable (i.e. the
    /// on-disk content decoded as text) -- gates the Save button.
    bool middleEditable_ = false;
    /// The on-disk content split into plain-text/region segments -- see
    /// ConflictMarkerParser. regionCount == 0 (no markers, or a malformed
    /// file the parser gave up on) means the middle column just shows
    /// on-disk content verbatim, same as before per-region resolution
    /// existed.
    ParsedConflictFile parsedMarkers_;
    /// One entry per parsedMarkers_ region, same order. Empty/Unresolved
    /// entries render as a placeholder line in buildMiddlePreviewText()
    /// rather than ever showing that region's raw marker text.
    std::vector<ConflictRegionResolution> regionResolutions_;
    /// Which region the strip's Prev/Next/Take buttons currently act on.
    int currentRegionIndex_ = 0;
    /// Each resolved region's [start, length) range in the text
    /// buildMiddlePreviewText() most recently produced -- see
    /// highlightCurrentRegion(). Empty once every region is resolved (the
    /// buffer switches to the assembled result, not that preview).
    std::vector<std::pair<int, int>> regionTextRanges_;

    /// Design A2's line-click bookkeeping. Index-aligned with
    /// parsedMarkers_'s region-only numbering (same as regionResolutions_),
    /// and each region's inner vector is index-aligned with
    /// regionSegment(regionIndex)->ours/theirs respectively. Empty until
    /// ensureCustomLineSelectionSeeded() first sizes it for that region.
    std::vector<std::vector<bool>> customOursLineSelected_;
    std::vector<std::vector<bool>> customTheirsLineSelected_;
    /// Whether ensureCustomLineSelectionSeeded() has already run for a
    /// given region -- can't infer this from the selection vectors' own
    /// emptiness, since a region with zero lines on one side (a valid
    /// conflict shape) would look identical to "not yet seeded".
    std::vector<bool> customLineSelectionSeeded_;
    /// A single click's target, so a following Shift+click in the *same*
    /// region and side can extend a range from it -- see
    /// onRegionLineToggled(). A Shift+click elsewhere (different region or
    /// side) just falls back to a plain toggle instead of guessing at a
    /// cross-side/region "range".
    struct LineClickAnchor {
        int regionIndex = 0;
        ConflictSide side = ConflictSide::Ours;
        int lineOffset = 0;
    };
    std::optional<LineClickAnchor> lastLineClickAnchor_;

    /// Raw on-disk blob text for each side, captured verbatim by
    /// onConflictSidesReady() rather than written straight into the edits --
    /// refreshSidePanes() needs it retained as the fallback render whenever
    /// parsedMarkers_.regionCount == 0 (no regions yet, or none at all).
    QString ancestorBlobText_;
    QString oursBlobText_;
    QString theirsBlobText_;

    QLabel* kindLabel_ = nullptr;
    QCheckBox* ancestorToggle_ = nullptr;
    QSplitter* panesSplitter_ = nullptr;
    QWidget* ancestorContainer_ = nullptr;
    ConflictTextEdit* ancestorEdit_ = nullptr;
    ConflictTextEdit* oursEdit_ = nullptr;
    ConflictTextEdit* middleEdit_ = nullptr;
    ConflictTextEdit* theirsEdit_ = nullptr;
    QPushButton* saveButton_ = nullptr;

    /// Per-region controls shown above the middle column, only while
    /// parsedMarkers_.regionCount > 0 -- see updateRegionStrip().
    QWidget* regionStrip_ = nullptr;
    QLabel* regionPositionLabel_ = nullptr;
    QPushButton* regionPrevButton_ = nullptr;
    QPushButton* regionNextButton_ = nullptr;
    QPushButton* regionTakeLeftButton_ = nullptr;
    QPushButton* regionTakeRightButton_ = nullptr;
    QPushButton* regionTakeLeftAllButton_ = nullptr;
    QPushButton* regionTakeRightAllButton_ = nullptr;
};

}  // namespace gbm
