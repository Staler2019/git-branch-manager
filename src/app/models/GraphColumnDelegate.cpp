#include "app/models/GraphColumnDelegate.h"

#include "app/bridge/ThemeManager.h"
#include "app/models/CommitListModel.h"

#include <QPainter>
#include <QPainterPath>
#include <QPen>

#include <algorithm>
#include <array>

namespace gbm {

GraphColumnDelegate::GraphColumnDelegate(CommitListModel* model, QObject* parent)
    : QStyledItemDelegate(parent), model_(model) {
    scratchEdges_.reserve(256);
}

QColor GraphColumnDelegate::laneColor(std::uint8_t index) {
    // Cycles through the theme's six `graph-lane-*` tokens rather than a
    // fixed 12-colour palette, so the graph re-colours with the rest of the
    // app when the theme changes.
    return ThemeManager::graphLane(index);
}

int GraphColumnDelegate::widthForRows(int firstRow, int lastRow) const {
    const auto snapshot = model_ == nullptr ? GraphSnapshotPtr{} : model_->snapshot();
    if (!snapshot || snapshot->rowCount() == 0) {
        return kLeftMargin + kLaneWidth;
    }
    const LaneId widest = snapshot->maxLaneInRange(static_cast<RowId>(std::max(0, firstRow)),
                                                   static_cast<RowId>(std::max(0, lastRow)));
    const int lanes = std::min<int>(static_cast<int>(widest) + 2, kMaxLanes + 1);
    return kLeftMargin * 2 + lanes * kLaneWidth;
}

QSize GraphColumnDelegate::sizeHint(const QStyleOptionViewItem& option,
                                    const QModelIndex& index) const {
    QSize size = QStyledItemDelegate::sizeHint(option, index);
    size.setHeight(std::max(size.height(), ThemeManager::rowHeight()));
    return size;
}

void GraphColumnDelegate::paint(QPainter* painter,
                                const QStyleOptionViewItem& option,
                                const QModelIndex& index) const {
    if (model_ == nullptr) {
        QStyledItemDelegate::paint(painter, option, index);
        return;
    }
    const auto snapshot = model_->snapshot();
    if (!snapshot) {
        QStyledItemDelegate::paint(painter, option, index);
        return;
    }

    const int row = index.row();
    if (row < 0 || row >= static_cast<int>(snapshot->rowCount())) {
        return;
    }

    const bool isSelected = (option.state & QStyle::State_Selected) != 0;

    // Selection background first, so the graph draws over it. Uses the same
    // @surface-selected token as every other column's selected background
    // (CommitRowDelegate, the plain QSS-styled Author/Date/ShortSha cells)
    // rather than option.palette.highlight() (@accent) -- a bright blue
    // graph cell next to a navy rest-of-row previously did not match.
    if (isSelected) {
        painter->fillRect(option.rect, ThemeManager::color(Token::SurfaceSelected));
    }

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);
    painter->setClipRect(option.rect);

    const QRect cell = option.rect;
    const int centerY = cell.center().y() + 1;
    const int top = cell.top();
    const int bottom = cell.bottom() + 1;
    const int left = cell.left();

    const RowMeta& meta = snapshot->rows[static_cast<std::size_t>(row)];

    // Only the edges touching this row and the next: the query is bounded by the
    // viewport, never by history size.
    snapshot->edgesInRange(static_cast<RowId>(row), static_cast<RowId>(row), scratchEdges_);

    // One path per colour, so a whole row is a handful of stroke calls.
    QHash<std::uint8_t, QPainterPath> pathsByColor;
    auto pathFor = [&pathsByColor](std::uint8_t color) -> QPainterPath& {
        return pathsByColor[color];
    };

    for (const Edge* edge : scratchEdges_) {
        const RowId end = edge->parentRow == kRowBoundary ? edge->childRow + 1 : edge->parentRow;
        const int laneX = laneCenterX(left, edge->lane);

        if (edge->childRow == static_cast<RowId>(row)) {
            // Starts here: leave the child's node and descend in this edge's lane.
            const int childX = laneCenterX(left, edge->childLane);
            QPainterPath& path = pathFor(edge->color);
            if (childX == laneX) {
                path.moveTo(laneX, centerY);
                path.lineTo(laneX, bottom);
            } else {
                // A single smooth bend out to the right, matching Fork's look.
                path.moveTo(childX, centerY);
                path.cubicTo(childX,
                             centerY + (bottom - centerY) / 2,
                             laneX,
                             centerY + (bottom - centerY) / 2,
                             laneX,
                             bottom);
            }
            continue;
        }

        if (end == static_cast<RowId>(row)) {
            // Ends here: descend to this row, then bend into the parent's lane.
            const int parentX = laneCenterX(left, meta.lane);
            QPainterPath& path = pathFor(edge->color);
            if (parentX == laneX) {
                path.moveTo(laneX, top);
                path.lineTo(laneX, centerY);
            } else {
                path.moveTo(laneX, top);
                path.cubicTo(laneX,
                             top + (centerY - top) / 2,
                             parentX,
                             top + (centerY - top) / 2,
                             parentX,
                             centerY);
            }
            continue;
        }

        // Passes straight through.
        QPainterPath& path = pathFor(edge->color);
        path.moveTo(laneX, top);
        path.lineTo(laneX, bottom);
    }

    for (auto it = pathsByColor.constBegin(); it != pathsByColor.constEnd(); ++it) {
        QPen pen(laneColor(it.key()));
        pen.setWidthF(1.8);
        pen.setCapStyle(Qt::RoundCap);
        pen.setJoinStyle(Qt::RoundJoin);
        painter->setPen(pen);
        painter->drawPath(it.value());
    }

    // --- the commit node -----------------------------------------------------
    const int nodeX = laneCenterX(left, meta.lane);
    const QColor color = laneColor(meta.color);

    if (meta.isOverflow()) {
        // Past the rendered lane cap. Drawn distinctly and counted in the UI rather
        // than silently omitted.
        QPen pen(color);
        pen.setStyle(Qt::DotLine);
        painter->setPen(pen);
        painter->setBrush(Qt::NoBrush);
        painter->drawEllipse(QPoint(nodeX, centerY), kNodeRadius, kNodeRadius);
    } else if (meta.isMerge()) {
        // Merges get a hollow ring, so the shape of history reads at a glance.
        painter->setPen(QPen(color, 2.0));
        painter->setBrush(option.palette.base());
        painter->drawEllipse(QPoint(nodeX, centerY), kNodeRadius, kNodeRadius);
    } else if (isSelected) {
        // A light outer ring with an accent-filled center, so the selected
        // row's node reads distinctly from an ordinary commit rather than
        // just sitting on a differently coloured background.
        painter->setPen(QPen(ThemeManager::color(Token::Accent), 1.0));
        painter->setBrush(ThemeManager::color(Token::Accent));
        painter->drawEllipse(QPoint(nodeX, centerY), kNodeRadius - 1, kNodeRadius - 1);
        QPen ringPen(ThemeManager::color(Token::TextPrimary));
        ringPen.setWidthF(1.4);
        painter->setPen(ringPen);
        painter->setBrush(Qt::NoBrush);
        painter->drawEllipse(QPoint(nodeX, centerY), kNodeRadius + 1, kNodeRadius + 1);
    } else {
        painter->setPen(QPen(color, 1.0));
        painter->setBrush(color);
        painter->drawEllipse(QPoint(nodeX, centerY), kNodeRadius - 1, kNodeRadius - 1);
    }

    if ((meta.flags & RowMeta::FlagIsHead) != 0) {
        QPen pen(option.palette.text().color());
        pen.setWidthF(1.2);
        painter->setPen(pen);
        painter->setBrush(Qt::NoBrush);
        painter->drawEllipse(QPoint(nodeX, centerY), kNodeRadius + 3, kNodeRadius + 3);
    }

    if (meta.isBoundary()) {
        // History continues past what was walked (a shallow clone, or a filter).
        QPen pen(color);
        pen.setStyle(Qt::DotLine);
        painter->setPen(pen);
        painter->drawLine(nodeX, centerY + kNodeRadius, nodeX, bottom);
    }

    painter->restore();
}

}  // namespace gbm
