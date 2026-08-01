#include "app/models/RefRowDelegate.h"

#include "app/bridge/ThemeManager.h"
#include "app/models/RefTreeModel.h"
#include "core/git/RefStore.h"

#include <QFontMetrics>
#include <QPainter>
#include <QPainterPath>
#include <QPen>

#include <algorithm>

namespace gbm {

namespace {

constexpr int kPillHeight = 20;
constexpr int kPillRadius = kPillHeight / 2;
constexpr int kPillHorizontalPad = 8;
constexpr int kSectionFontSize = 11;  // ~10.5px, rounded to an integer pixel size.
constexpr int kPillFontSize = 11;

struct PillColors {
    QColor text;
    QColor border;
    QColor fill;  ///< Invalid (default QColor()) means no fill, border only.
};

PillColors pillColorsFor(RefKind kind, bool isHead) {
    switch (kind) {
        case RefKind::LocalBranch:
            if (isHead) {
                return {ThemeManager::color(Token::TextOnAccent),
                        ThemeManager::color(Token::Accent),
                        ThemeManager::color(Token::Accent)};
            }
            return {ThemeManager::color(Token::Accent),
                    ThemeManager::color(Token::AccentSubtle),
                    ThemeManager::color(Token::AccentSubtle)};
        case RefKind::Tag:
            return {ThemeManager::color(Token::Warning),
                    ThemeManager::color(Token::BorderDefault),
                    QColor()};
        case RefKind::RemoteBranch:
        default:
            return {ThemeManager::color(Token::TextTertiary),
                    ThemeManager::color(Token::BorderDefault),
                    QColor()};
    }
}

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
        QFont font = ThemeManager::uiFont(kSectionFontSize);
        font.setBold(true);
        font.setCapitalization(QFont::AllUppercase);
        font.setLetterSpacing(QFont::AbsoluteSpacing, 0.5);
        painter->setFont(font);
        painter->setPen(ThemeManager::color(Token::TextTertiary));
        painter->drawText(option.rect, Qt::AlignVCenter | Qt::AlignLeft, opt.text);
        painter->restore();
        return;
    }

    // isRef: paint a gbm-tag pill.
    const auto kind = static_cast<RefKind>(index.data(RefTreeModel::RefKindRole).toInt());
    const bool isHead = index.data(RefTreeModel::IsHeadRole).toBool();
    const PillColors colors = pillColorsFor(kind, isHead);

    QFont font = ThemeManager::monoFont(kPillFontSize);
    painter->setFont(font);
    const QFontMetrics metrics(font);
    const int textWidth = metrics.horizontalAdvance(opt.text);
    const int pillWidth =
        std::min(textWidth + kPillHorizontalPad * 2, option.rect.width() - option.rect.height());
    QRect pillRect(option.rect.left(),
                   option.rect.top() + (option.rect.height() - kPillHeight) / 2,
                   std::max(pillWidth, kPillHeight),
                   kPillHeight);

    QPainterPath path;
    path.addRoundedRect(pillRect, kPillRadius, kPillRadius);
    if (colors.fill.isValid()) {
        painter->fillPath(path, colors.fill);
    }
    painter->setPen(QPen(colors.border, 1));
    painter->drawPath(path);

    painter->setPen(colors.text);
    painter->drawText(pillRect, Qt::AlignCenter, opt.text);

    painter->restore();
}

}  // namespace gbm
