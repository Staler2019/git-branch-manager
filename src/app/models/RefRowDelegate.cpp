#include "app/models/RefRowDelegate.h"

#include "app/bridge/ThemeManager.h"
#include "app/models/PillPainter.h"
#include "app/models/RefTreeModel.h"
#include "core/git/RefStore.h"

#include <QFontMetrics>
#include <QPainter>

#include <algorithm>

namespace gbm {

namespace {

constexpr int kPillFontSize = 11;

}  // namespace

RefRowDelegate::RefRowDelegate(QObject* parent) : QStyledItemDelegate(parent) {}

QSize RefRowDelegate::sizeHint(const QStyleOptionViewItem& option, const QModelIndex& index) const {
    QSize size = QStyledItemDelegate::sizeHint(option, index);
    size.setHeight(std::max(size.height(), ThemeManager::rowHeight()));
    return size;
}

void RefRowDelegate::paint(QPainter* painter,
                           const QStyleOptionViewItem& option,
                           const QModelIndex& index) const {
    const bool isSection = index.data(RefTreeModel::IsSectionRole).toBool();
    const bool isRef = index.data(RefTreeModel::IsRefRole).toBool();

    if (!isSection && !isRef) {
        // An intermediate slash-separated grouping node -- ordinary tree label.
        QStyledItemDelegate::paint(painter, option, index);
        return;
    }

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);

    // Background: hover/selected state, same as the plain tree rows around it.
    QStyleOptionViewItem opt = option;
    initStyleOption(&opt, index);
    if (opt.state & QStyle::State_Selected) {
        painter->fillRect(option.rect, ThemeManager::color(Token::SurfaceSelected));
    } else if (opt.state & QStyle::State_MouseOver) {
        painter->fillRect(option.rect, ThemeManager::color(Token::SurfaceHover));
    }

    if (isSection) {
        painter->setFont(ThemeManager::sectionHeaderFont());
        painter->setPen(ThemeManager::color(Token::TextTertiary));
        painter->drawText(option.rect, Qt::AlignVCenter | Qt::AlignLeft, opt.text);
        painter->restore();
        return;
    }

    // isRef: paint a gbm-tag pill, via the same PillPainter CommitRowDelegate
    // uses for commit-row ref chips -- one implementation for both.
    const auto kind = static_cast<RefKind>(index.data(RefTreeModel::RefKindRole).toInt());
    const bool isHead = index.data(RefTreeModel::IsHeadRole).toBool();
    const PillColors colors = PillPainter::colorsForRef(kind, isHead);

    const QFont font = ThemeManager::monoFont(kPillFontSize);
    const QFontMetrics metrics(font);
    const int pillWidth = std::min(PillPainter::widthFor(opt.text, metrics),
                                   option.rect.width() - option.rect.height());
    const QRect pillRect(option.rect.left(),
                         option.rect.top() + (option.rect.height() - PillPainter::kHeight) / 2,
                         std::max(pillWidth, PillPainter::kHeight),
                         PillPainter::kHeight);
    PillPainter::paint(painter, pillRect, opt.text, font, colors);

    painter->restore();
}

}  // namespace gbm
