#pragma once

#include "app/views/ConflictTextEdit.h"
#include "core/git/ConflictMarkerParser.h"
#include "core/git/TextTraits.h"

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

/// Design A3's reset confirmation gate: once every region is resolved,
/// `middleEdit_` becomes the user's freely-editable buffer (see
/// refreshMiddleFromResolutions()) -- `currentText` may have since diverged
/// from `lastAssembledText` (the exact text last written when the buffer
/// became editable) by the user's own typing. Resetting one region back to
/// Unresolved re-renders that buffer from the per-region preview, discarding
/// any such divergence, so this is the predicate resetRegionToUnresolved()
/// checks before doing that silently. A free function (not a member) so it's
/// directly unit-testable without constructing a panel or session -- same
/// reasoning as buildSidePaneText()/composeCustomRegionLines() in
/// ConflictTextEdit.h.
///
/// `isReadOnly` short-circuits to false: while any region remains
/// Unresolved the buffer is still the per-region preview, not the user's
/// free-editing buffer, so there is nothing of theirs to lose yet no matter
/// what the two strings say (they're expected to differ constantly while
/// still previewing).
bool middleBufferHasUnsavedEdits(const QString& currentText, const QString& lastAssembledText,
                                  bool isReadOnly);

/// Design A5: what to show/restrict for one pair of sides' TextTraits.
///
/// Line-ending badges/warning are diff-based only -- must_not_do: "不得在行
/// 尾一致時顯示徽章或警告列" (never show a badge or warning when the two
/// sides' line endings already agree). A side reporting
/// LineEndingKind::None (an empty or single-line blob has no line-ending
/// opinion of its own) never participates in that comparison either way --
/// there is nothing for it to disagree with, so `lineEndingsDiffer` stays
/// false whenever either side is None. `oursBadge`/`theirsBadge` carry the
/// raw technical token (LF, CRLF, Mixed, Non-UTF-8, ...) untranslated,
/// matching how this app leaves other protocol-level acronyms alone; the
/// surrounding sentence is composed and translated by the caller
/// (ConflictResolvePanel::updateTraitsPresentation(), a member function so
/// tr() is available -- this one is a free function so it stays directly
/// unit-testable, same reasoning as middleBufferHasUnsavedEdits() above).
///
/// Encoding badges/unsafe flags are the opposite of diff-based: each side's
/// badge and *LineOpsUnsafe flag come from that side's own encoding alone,
/// independent of the other side's. Design A5's must_not_do only ties a
/// column's badge to its own restriction ("停用該欄的拖曳與點行...並在該欄
/// 標明原因"), not to whether the other column also happens to be unsafe.
/// Utf8/Utf8Bom are the only encodings considered safe for per-line
/// composition; NonUtf8, Binary, and both UTF-16 variants are all "not
/// valid UTF-8" per the plan's literal wording and are therefore unsafe --
/// per-line drag/click on that side would silently mix encodings into
/// middleEdit_'s otherwise-UTF-8 buffer.
struct ConflictTraitsSummary {
    QString oursBadge;
    QString theirsBadge;
    bool lineEndingsDiffer = false;
    bool oursLineOpsUnsafe = false;
    bool theirsLineOpsUnsafe = false;
};

/// Pure/testable core of Design A5's presentation and restriction rules --
/// see ConflictTraitsSummary's own doc comment for exactly which fields are
/// diff-based and which are absolute per-side.
ConflictTraitsSummary summarizeConflictSideTraits(const TextTraits& ours, const TextTraits& theirs);

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

    /// Design B1 (C13): whether the file currently loaded has conflict-
    /// resolution choices that have not gone through submitResolution() yet
    /// -- a region already given a choice, a hand-edit to the fully-
    /// assembled middleEdit_ buffer once every region has one, or (for a
    /// regionCount == 0 whole-file conflict) a hand-edit to the raw on-disk
    /// content itself. False once submitResolution() has gone through for
    /// this file, and false again from showEntry() on for whatever comes
    /// next -- see submitResolution()'s own comment on why nothing further
    /// back than "the file on screen right now" needs checking here: every
    /// earlier file in the batch was already written via
    /// session_->resolveConflict() at the moment its own Save fired.
    bool hasUnsavedProgress() const;

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
    /// Design A5: ancestor's traits are received but deliberately unused --
    /// the ancestor pane is never a drag/click source (see setSide()'s own
    /// comment) and never gets a badge, so there is nothing for its traits
    /// to gate. See RepositorySession::conflictSideTraitsReady's own comment
    /// on why this is a separate signal from conflictSidesReady rather than
    /// an extension of it.
    void onConflictSideTraitsReady(const QString& path, const TextTraits& ancestor,
                                    const TextTraits& ours, const TextTraits& theirs);
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

    /// Design A5: re-derives a ConflictTraitsSummary from oursTraits_/
    /// theirsTraits_ and applies it -- badge text + visibility on
    /// oursTraitBadge_/theirsTraitBadge_, the combined warning sentence(s)
    /// on traitsWarningRow_/traitsWarningLabel_. Does *not* touch
    /// regionSpans_ on either pane itself -- refreshSidePanes() reads the
    /// same summary to decide that, so the two stay in lockstep by always
    /// being called together (see onConflictSideTraitsReady()).
    void updateTraitsPresentation();

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
    /// Take Left/Take Right (plain Ours/Theirs, no custom lines), their
    /// keyboard equivalents (Left/Right -- Design A3, see the constructor's
    /// QShortcut wiring), and dragging a region onto the middle pane (plain
    /// Ours/Theirs, via ConflictTextEdit::regionDropped()).
    void resolveRegion(int index, ConflictRegionResolution resolution);
    /// Take-left/take-right applied to every region at once.
    void resolveAllRegions(ConflictRegionChoice choice);
    /// Design A3: sets regionResolutions_[index] back to Unresolved -- the
    /// direct-manipulation surface's one recovery path (must_not_do:
    /// "每個區塊都要能一鍵重設回未解決"), reachable via regionResetButton_ or
    /// the Backspace shortcut. A no-op if the region is already Unresolved.
    /// Guarded by middleBufferHasUnsavedEdits(): once every region is
    /// resolved, resetting one would silently re-render (and thus discard)
    /// anything the user has typed into the now-editable middleEdit_ since
    /// it became editable, so that case asks for confirmation first rather
    /// than eating the edit outright -- unlike the drop/Take Left/Right
    /// hazard elsewhere, reset must still be able to go through once
    /// confirmed, since "undo my last per-region choice" is the whole point
    /// of the affordance.
    void resetRegionToUnresolved(int index);
    /// Moves currentRegionIndex_ by `delta`, clamped to the valid range.
    void navigateRegion(int delta);
    /// Reflects currentRegionIndex_ (position, resolved state, prev/next
    /// enablement, and regionResetButton_'s enabled state) onto the strip
    /// widgets. No-op when regionCount == 0.
    void updateRegionStrip();
    /// Design A3: shows directManipulationHintRow_ iff regionStrip_ is
    /// currently visible (there is direct-manipulation UI to explain) and
    /// the user hasn't dismissed it before (QSettings
    /// "conflictResolve/hintDismissed") -- called everywhere
    /// regionStrip_->setVisible() is, so the two never fall out of sync.
    void updateDirectManipulationHintVisibility();
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
    /// Paints every line on the winning side's gutter as checked (and
    /// clears the other side's) for a whole-side resolution -- Take Left/
    /// Right, Take All, or a region dropped onto the middle pane. Without
    /// this, only line-by-line Custom picks (onRegionLineToggled()) ever
    /// showed the check-mark affordance; a whole-side choice left the
    /// source pane looking untouched even though it fully contributed.
    /// Only call after resetCustomLineSelection(regionIndex) -- this does
    /// not touch customLineSelectionSeeded_, so a later line click still
    /// starts lazily seeded via ensureCustomLineSelectionSeeded() rather
    /// than through this display-only path.
    void showWholeSideLineSelection(int regionIndex, ConflictRegionChoice choice);

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
    /// Design B1 (C13): true once submitResolution() has gone through for
    /// whichever file is currently loaded -- reset to false by showEntry()
    /// for the next file and by every mutation of regionResolutions_
    /// (resolveRegion()/resolveAllRegions()/resetRegionToUnresolved()), so a
    /// change made *after* a save (however unlikely before the window moves
    /// on) still counts as unsaved again. See hasUnsavedProgress().
    bool submittedCurrentEntry_ = false;
    /// The regionCount == 0 whole-file-edit path's baseline for
    /// hasUnsavedProgress() -- the content as loaded, before any hand-edit.
    /// Unlike lastAssembledMiddleText_ (which only means something once
    /// every region is resolved), this path never goes through
    /// refreshMiddleFromResolutions() at all, so it needs its own baseline.
    QString wholeFileBaselineText_;
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
    /// The exact text refreshMiddleFromResolutions() last wrote into
    /// middleEdit_ when it switched to the fully-assembled, editable result
    /// (every region resolved) -- empty whenever that isn't the current
    /// state. Compared against middleEdit_->toPlainText() by
    /// middleBufferHasUnsavedEdits() so resetRegionToUnresolved() knows
    /// whether the user has typed anything into that buffer since, and
    /// therefore whether resetting a region would silently discard it.
    QString lastAssembledMiddleText_;

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

    /// Design A5: the two sides' undecoded-byte traits, as last reported by
    /// RepositorySession::conflictSideTraitsReady(). Default-constructed
    /// (TextTraits{}, i.e. LineEndingKind::None on both, EncodingKind::Utf8
    /// on both) until that reply arrives -- summarizeConflictSideTraits()
    /// treats that as "nothing to disagree about", so no badge/warning
    /// shows and no pane is restricted before the reply lands, rather than
    /// showing a false positive from two stale/default values.
    TextTraits oursTraits_;
    TextTraits theirsTraits_;

    QLabel* kindLabel_ = nullptr;
    QCheckBox* ancestorToggle_ = nullptr;
    /// Design A5's file-level warning banner -- see updateTraitsPresentation().
    /// Sits above regionStrip_ since it reflects the blob-level traits, not
    /// anything region-parsing-dependent, so it's relevant even for a
    /// regionCount == 0 file.
    QWidget* traitsWarningRow_ = nullptr;
    QLabel* traitsWarningLabel_ = nullptr;
    QSplitter* panesSplitter_ = nullptr;
    QWidget* ancestorContainer_ = nullptr;
    /// ancestorEdit_/oursEdit_/theirsEdit_ are permanently Qt::NoFocus --
    /// pure display/hover/drag surfaces, never a typing target (see
    /// makePane() in the .cpp). middleEdit_ toggles between Qt::NoFocus and
    /// Qt::StrongFocus in lockstep with its own setReadOnly() calls, gaining
    /// keyboard focus only once it is genuinely the free-editing buffer --
    /// otherwise Design A3's Left/Right/Backspace shortcuts (constructor)
    /// would be silently unreachable the moment any pane took focus, since a
    /// focused QPlainTextEdit claims those keys as its own cursor-navigation
    /// keys before the shortcut ever gets a chance.
    ConflictTextEdit* ancestorEdit_ = nullptr;
    ConflictTextEdit* oursEdit_ = nullptr;
    ConflictTextEdit* middleEdit_ = nullptr;
    ConflictTextEdit* theirsEdit_ = nullptr;
    /// Design A5's per-column badges (e.g. "CRLF", "Non-UTF-8") -- hidden
    /// (empty text) whenever ConflictTraitsSummary has nothing to say about
    /// that side. See updateTraitsPresentation(). No ancestor/middle
    /// equivalent -- the ancestor pane is never a drag/click source and the
    /// middle pane isn't either side, so neither ever needs one.
    QLabel* oursTraitBadge_ = nullptr;
    QLabel* theirsTraitBadge_ = nullptr;
    QPushButton* saveButton_ = nullptr;

    /// Per-region controls shown above the middle column, only while
    /// parsedMarkers_.regionCount > 0 -- see updateRegionStrip(). Take
    /// Left/Take Right (per-region) were removed in Design A3: dragging a
    /// region onto the middle pane (Commit 6) and the Left/Right keyboard
    /// shortcuts below now cover that same action, and keeping a third,
    /// redundant pair of buttons around just for symmetry would have
    /// widened regionStrip_ again for no reason.
    QWidget* regionStrip_ = nullptr;
    QLabel* regionPositionLabel_ = nullptr;
    QPushButton* regionPrevButton_ = nullptr;
    QPushButton* regionNextButton_ = nullptr;
    /// Design A3's recovery affordance -- resets the *current* region back
    /// to Unresolved; see resetRegionToUnresolved(). Disabled while the
    /// current region already is Unresolved (nothing to reset).
    QPushButton* regionResetButton_ = nullptr;
    QPushButton* regionTakeLeftAllButton_ = nullptr;
    QPushButton* regionTakeRightAllButton_ = nullptr;

    /// Design A3's first-use hint: a single dismissible row below
    /// regionStrip_ explaining the drag/click interactions, since neither is
    /// discoverable on its own (ux3.rule.mental_model_alignment) -- see
    /// updateDirectManipulationHintVisibility(). Mirrors
    /// MainWindow's perfHintRow_ dismissible-hint pattern.
    QWidget* directManipulationHintRow_ = nullptr;
    QLabel* directManipulationHintLabel_ = nullptr;
    QPushButton* directManipulationHintDismissButton_ = nullptr;
};

}  // namespace gbm
