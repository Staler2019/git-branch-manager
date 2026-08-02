#pragma once

#include <QStyledItemDelegate>

namespace gbm {

/// Shared row painting for the sidebar's Repositories and Stash sections --
/// the only two that still used a stock delegate (Branches/Remotes/Tags
/// already have `RefRowDelegate`). Repository rows draw an icon (which one
/// depends on `RepoListModel::KindRole`) plus an ahead/behind
/// `.gbm-badge-neutral`-style pill; stash rows draw an `archive` icon plus
/// elided text. Both draw the same inset, rounded selection/hover
/// background -- the reason `resources/qss/app.qss` makes `::item` fully
/// transparent for the views this delegate is installed on.
class SidebarRowDelegate : public QStyledItemDelegate {
    Q_OBJECT

public:
    enum class Kind { Repository, Stash };

    explicit SidebarRowDelegate(Kind kind, QObject* parent = nullptr);

    QSize sizeHint(const QStyleOptionViewItem& option, const QModelIndex& index) const override;
    void paint(QPainter* painter,
               const QStyleOptionViewItem& option,
               const QModelIndex& index) const override;

private:
    Kind kind_;
};

}  // namespace gbm
