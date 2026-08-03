#pragma once

#include "core/git/DiffService.h"
#include "core/git/UnifiedDiffParser.h"

#include <QModelIndex>
#include <QWidget>

#include <memory>
#include <vector>

class QLabel;
class QScrollArea;
class QVBoxLayout;

namespace gbm {

/// The panel `MainWindow` installs via `QTableView::setIndexWidget` when a
/// selected commit row is expanded in place (`MainWindow::expandCommitRow`).
///
/// Root cause this replaces: the previous panel only covered the Subject
/// cell while `setRowHeight` grew the *whole* row, so Author/Date/ShortSha
/// kept painting -- vertically re-centered in the taller row -- on top of
/// (or behind) the panel, and the graph delegate ran lane lines down the
/// full height. Fixed here by having `MainWindow` span the whole row (see
/// `expandCommitRow`) and by painting this panel's own top strip through
/// `CommitRowDelegate::paintRow` -- the exact routine every collapsed row
/// uses -- rather than hand-building a second summary layout that could
/// drift from it.
///
/// Layout: a reserved top band (this widget's own `paintEvent`, height
/// `ThemeManager::rowHeight()`) showing the commit summary line exactly as
/// the collapsed row would, then a rounded card beneath listing changed
/// files with +added/-removed badges. More than a handful of files scrolls
/// inside the card rather than being truncated behind a "+N more" label.
class CommitExpansionPanel : public QWidget {
    Q_OBJECT

public:
    /// `commitIndex` must be the Subject-column index for the expanded row
    /// (`model->index(row, CommitListModel::ColumnSubject)`) -- `Qt::DisplayRole`
    /// is column-dependent, so any other column would paint the wrong text.
    explicit CommitExpansionPanel(QPersistentModelIndex commitIndex, QWidget* parent = nullptr);

    /// Populates the file list once details arrive -- see
    /// `MainWindow::refreshExpandedCommitPanel`. Safe to call more than once
    /// (a re-expand after a refresh rebuilds the same panel from scratch).
    void setDetails(std::shared_ptr<const std::vector<ChangedFile>> files,
                    std::shared_ptr<const ParsedDiff> diff);

protected:
    void paintEvent(QPaintEvent* event) override;

private:
    void rebuildFileList();

    static constexpr int kMaxVisibleFileRows = 6;
    static constexpr int kFileRowHeight = 22;

    QPersistentModelIndex commitIndex_;
    std::shared_ptr<const std::vector<ChangedFile>> files_;
    std::shared_ptr<const ParsedDiff> diff_;
    bool hasDetails_ = false;

    QWidget* card_ = nullptr;
    QVBoxLayout* cardLayout_ = nullptr;
    QLabel* summaryLabel_ = nullptr;
    QScrollArea* fileScroll_ = nullptr;
    QWidget* fileListWidget_ = nullptr;
    QVBoxLayout* fileListLayout_ = nullptr;
};

}  // namespace gbm
