#pragma once

#include <QPlainTextEdit>
#include <QWidget>

namespace gbm {

/// Read-only, line-numbered viewer for one file's content at a fixed
/// revision -- the Working Copy view's "Original (HEAD)" tab (item 8). Unlike
/// DiffView/SideBySideDiffView, there is no patch to build here and nothing to
/// stage: this shows a plain blob, not a diff, so it carries no colour tint of
/// its own. The "use colours to show the differences" part of item 8 is
/// satisfied by the Working-changes and Staged tabs next to it, which are full
/// colour-coded diffs; duplicating that tinting here (by diffing against the
/// working tree a second time) would be display logic this tab does not need.
class FileContentView : public QWidget {
    Q_OBJECT

public:
    explicit FileContentView(QWidget* parent = nullptr);

    /// Shows `content` as-is (already-decoded text; binary blobs are the
    /// caller's problem to detect and substitute a message for instead).
    void showContent(const QString& content);

    /// A non-content status line -- "Loading…", or "This file does not exist
    /// at this revision" for a brand-new untracked file, which has no `HEAD`
    /// side at all.
    void showMessage(const QString& message);

    void clear();

    /// Re-applies the theme's mono font and gutter colours after a theme
    /// switch. No per-line colour is baked in here (see class comment), so
    /// this is a lighter re-application than DiffView::refreshTheme.
    void refreshTheme();

private:
    QPlainTextEdit* text_ = nullptr;
    QWidget* gutter_ = nullptr;
};

}  // namespace gbm
