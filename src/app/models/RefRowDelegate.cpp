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
constexpr int kBadgeGap = 6;  ///< Matches SidebarRowDelegate's badge inset.

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

    // A right-aligned "gone" badge for a local branch whose upstream no
    // longer exists (RefStore's [gone] marker, surfaced as IsGoneRole).
    // badgeWidth stays 0 for every other row, which makes `available` below
    // literally today's `option.rect.width() - option.rect.height()` and
    // nameText literally opt.text -- non-gone rows are provably unchanged.
    const bool isGone = index.data(RefTreeModel::IsGoneRole).toBool();
    const QString badgeText = QStringLiteral("gone");
    const QFont badgeFont = ThemeManager::monoFont(kPillFontSize);
    int badgeWidth =
        isGone ? PillPainter::widthFor(badgeText, QFontMetrics(badgeFont)) + kBadgeGap : 0;

    int available = std::max(option.rect.width() - option.rect.height() - badgeWidth, 0);
    if (available < PillPainter::kHeight) {
        // Too narrow for both -- drop the badge rather than let it overlap
        // the name pill; the tooltip still carries the information.
        badgeWidth = 0;
        available = std::max(option.rect.width() - option.rect.height(), 0);
    }

    const QString nameText =
        badgeWidth > 0 ? metrics.elidedText(opt.text, Qt::ElideMiddle, available) : opt.text;
    const int pillWidth = std::min(PillPainter::widthFor(nameText, metrics), available);
    const QRect pillRect(option.rect.left(),
                         option.rect.top() + (option.rect.height() - PillPainter::kHeight) / 2,
                         std::max(pillWidth, PillPainter::kHeight),
                         PillPainter::kHeight);
    PillPainter::paint(painter, pillRect, nameText, font, colors);

    if (badgeWidth > 0) {
        // Mirrors Tag's own "outline" treatment (colorsForRef) rather than an
        // invalid fill: an unfilled pill composites straight onto whatever
        // the view painted behind it and reads poorly on a selected row.
        const PillColors goneColors{ThemeManager::color(Token::Warning),
                                    ThemeManager::color(Token::BorderDefault),
                                    ThemeManager::color(Token::SurfaceHover)};
        const int badgePillWidth = badgeWidth - kBadgeGap;
        const QRect badgeRect(option.rect.right() - kBadgeGap - badgePillWidth,
                              option.rect.top() + (option.rect.height() - PillPainter::kHeight) / 2,
                              badgePillWidth,
                              PillPainter::kHeight);
        PillPainter::paint(painter, badgeRect, badgeText, badgeFont, goneColors);
    }

    painter->restore();
}

}  // namespace gbm
