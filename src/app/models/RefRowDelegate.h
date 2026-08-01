#pragma once

#include <QStyledItemDelegate>

namespace gbm {

/// Paints the sidebar's Branches/Remotes/Tags tree.
///
/// QSS cannot style one row of a `QTreeView` differently from another --
/// `GraphColumnDelegate` is why this app already hand-paints anything that
/// needs per-row colour, and this follows the same precedent rather than
/// inventing a second mechanism. Three row shapes:
///
///  * A top-level section root ("Branches" / "Remotes" / "Tags",
///    `RefTreeModel::IsSectionRole`) -- uppercase, 10.5px, tertiary text, no
///    pill, not selectable-looking.
///  * A leaf ref (`RefTreeModel::IsRefRole`) -- a `gbm-tag` pill per
///    `docs/design/tokens-reference.md`: local branches accent-outlined
///    (accent-filled when it is HEAD), remote branches tertiary-outlined,
///    tags warning-coloured. Mono font, matching the design's `.gbm-tag`.
///  * An intermediate slash-separated grouping node (e.g. "feature/") --
///    left exactly as `QStyledItemDelegate` already renders it.
class RefRowDelegate : public QStyledItemDelegate {
    Q_OBJECT

public:
    explicit RefRowDelegate(QObject* parent = nullptr);

    void paint(QPainter* painter,
               const QStyleOptionViewItem& option,
               const QModelIndex& index) const override;

    QSize sizeHint(const QStyleOptionViewItem& option, const QModelIndex& index) const override;
};

}  // namespace gbm
