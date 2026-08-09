#pragma once

#include <QPlainTextEdit>

class QPaintEvent;
class QResizeEvent;
class QRect;
class QWidget;

namespace gbm {

/// A read-only-friendly QPlainTextEdit with a line-number gutter in its
/// viewport margin -- the standard Qt "Code Editor" example pattern
/// (firstVisibleBlock/blockBoundingGeometry are protected on QPlainTextEdit,
/// so a companion LineNumberArea widget can only reach them through a
/// subclass). Used for all four panes (ancestor/ours/result/theirs) in
/// ConflictResolvePanel. Extracted from ConflictResolvePanel.cpp into its own
/// file because it is about to grow hover/drag-and-drop/line-pick behaviour
/// for direct-manipulation conflict resolution, which would push
/// ConflictResolvePanel.cpp well past this codebase's 800-line file guidance.
class ConflictTextEdit : public QPlainTextEdit {
public:
    explicit ConflictTextEdit(QWidget* parent = nullptr);

protected:
    void resizeEvent(QResizeEvent* event) override;

private:
    friend class LineNumberArea;
    int lineNumberAreaWidth() const;
    void lineNumberAreaPaintEvent(QPaintEvent* event);
    void updateLineNumberAreaWidth(int newBlockCount);
    void updateLineNumberArea(const QRect& rect, int dy);

    QWidget* lineNumberArea_ = nullptr;
};

}  // namespace gbm
