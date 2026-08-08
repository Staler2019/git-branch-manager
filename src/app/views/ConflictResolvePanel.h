#pragma once

#include "core/git/ConflictMarkerParser.h"

#include <QWidget>

#include <string>
#include <utility>

class QCheckBox;
class QLabel;
class QPlainTextEdit;
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
    /// Sets `regionResolutions_[index]` to a plain Ours/Theirs choice (no
    /// custom lines), re-renders, and jumps to the next still-unresolved
    /// region if there is one, so working through a batch of conflicts is a
    /// straight line of clicks.
    void resolveRegion(int index, ConflictRegionChoice choice);
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

    QLabel* kindLabel_ = nullptr;
    QCheckBox* ancestorToggle_ = nullptr;
    QSplitter* panesSplitter_ = nullptr;
    QWidget* ancestorContainer_ = nullptr;
    QPlainTextEdit* ancestorEdit_ = nullptr;
    QPlainTextEdit* oursEdit_ = nullptr;
    QPlainTextEdit* middleEdit_ = nullptr;
    QPlainTextEdit* theirsEdit_ = nullptr;
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
