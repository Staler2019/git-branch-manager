#pragma once

#include <QStyledItemDelegate>

class QRect;

namespace gbm {

/// Paints the commit list's Subject column: elided subject text, then up to
/// three right-aligned ref-chip pills (`main`, `v0.5.0`, `origin/main`, ...)
/// via `PillPainter` -- the same pill `RefRowDelegate` already paints for the
/// sidebar, so a commit row and a sidebar ref never draw two different-looking
/// pills for the same kind of ref.
///
/// `paintRow()` is exposed as public, static API deliberately: it is also
/// called directly by `CommitExpansionPanel`'s summary strip (a plain
/// `QWidget`, not a delegate), so the expanded row's top strip is pixel-for-
/// pixel the same layout as every collapsed row instead of a second,
/// independently drifting implementation of "what a commit row looks like".
class CommitRowDelegate : public QStyledItemDelegate {
    Q_OBJECT

public:
    explicit CommitRowDelegate(QObject* parent = nullptr);

    void paint(QPainter* painter,
               const QStyleOptionViewItem& option,
               const QModelIndex& index) const override;

    /// `selected`/`hovered` are passed explicitly rather than read off a
    /// `QStyleOptionViewItem` because `CommitExpansionPanel` has no such
    /// option to read from -- it is a plain widget, not a view item.
    static void paintRow(QPainter* painter,
                        const QRect& rect,
                        const QModelIndex& index,
                        bool selected,
                        bool hovered = false);

private:
    static constexpr int kMaxChips = 3;
};

}  // namespace gbm
