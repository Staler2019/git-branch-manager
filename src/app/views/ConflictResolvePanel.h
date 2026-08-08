#pragma once

#include "core/git/ConflictMarkerParser.h"

#include <QWidget>

#include <string>

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
    QString buildMiddlePreviewText() const;

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

    QLabel* kindLabel_ = nullptr;
    QCheckBox* ancestorToggle_ = nullptr;
    QSplitter* panesSplitter_ = nullptr;
    QWidget* ancestorContainer_ = nullptr;
    QPlainTextEdit* ancestorEdit_ = nullptr;
    QPlainTextEdit* oursEdit_ = nullptr;
    QPlainTextEdit* middleEdit_ = nullptr;
    QPlainTextEdit* theirsEdit_ = nullptr;
    QPushButton* saveButton_ = nullptr;
};

}  // namespace gbm
