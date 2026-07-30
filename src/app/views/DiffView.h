#pragma once

#include "core/git/UnifiedDiffParser.h"

#include <QPlainTextEdit>
#include <QWidget>

#include <memory>

namespace gbm {

/// Unified diff viewer.
///
/// Built on QPlainTextEdit rather than a custom widget for one decisive reason:
/// users copy code out of diffs, and text selection, find and keyboard navigation
/// come free and behave natively. QPlainTextEdit also handles very long documents
/// without laying out the whole thing up front.
class DiffView : public QPlainTextEdit {
    Q_OBJECT

public:
    explicit DiffView(QWidget* parent = nullptr);

    void showDiff(std::shared_ptr<const ParsedDiff> diff);

    /// Shows a single file from a multi-file diff.
    void showFile(std::shared_ptr<const ParsedDiff> diff, const QString& path);

    void showMessage(const QString& message);

    void clearDiff();

private:
    void render(const ParsedDiff& diff, const QString& onlyPath);

    std::shared_ptr<const ParsedDiff> diff_;
};

}  // namespace gbm
