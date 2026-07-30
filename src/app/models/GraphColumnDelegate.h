#pragma once

#include "core/graph/GraphSnapshot.h"

#include <QColor>
#include <QStyledItemDelegate>
#include <QVector>

#include <vector>

namespace gbm {

class CommitListModel;

/// Paints the commit graph gutter.
///
/// Two things keep this fast enough to scroll a 500k-row history at 60 fps:
///
///  * Geometry comes from an interval query over the snapshot's edge list, so the
///    cost is proportional to the number of edges crossing the viewport, not to
///    history size.
///  * Segments are batched into one `QPainterPath` per colour for the whole
///    viewport, so a screenful costs roughly a dozen draw calls instead of several
///    per row.
class GraphColumnDelegate : public QStyledItemDelegate {
    Q_OBJECT

public:
    explicit GraphColumnDelegate(CommitListModel* model, QObject* parent = nullptr);

    void paint(QPainter* painter,
               const QStyleOptionViewItem& option,
               const QModelIndex& index) const override;

    QSize sizeHint(const QStyleOptionViewItem& option, const QModelIndex& index) const override;

    /// Width needed for the lanes actually in use across the given rows, so the
    /// gutter can shrink when history is linear instead of being sized for the
    /// busiest era.
    int widthForRows(int firstRow, int lastRow) const;

    static QColor laneColor(std::uint8_t index);

private:
    static constexpr int kLaneWidth = 14;
    static constexpr int kNodeRadius = 4;
    static constexpr int kLeftMargin = 6;

    static int laneCenterX(int left, LaneId lane) {
        return left + kLeftMargin + static_cast<int>(lane) * kLaneWidth + kLaneWidth / 2;
    }

    CommitListModel* model_;

    /// Reused across paints to keep the hot path allocation-free.
    mutable std::vector<const Edge*> scratchEdges_;
};

}  // namespace gbm
