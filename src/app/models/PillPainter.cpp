#include "app/models/PillPainter.h"

#include "app/bridge/ThemeManager.h"

#include <QPainter>
#include <QPainterPath>
#include <QPen>

#include <algorithm>

namespace gbm {

int PillPainter::widthFor(const QString& text, const QFontMetrics& metrics) {
    return std::max(metrics.horizontalAdvance(text) + kHorizontalPad * 2, kHeight);
}

void PillPainter::paint(QPainter* painter,
                        const QRect& rect,
                        const QString& text,
                        const QFont& font,
                        const PillColors& colors) {
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);
    painter->setFont(font);

    QPainterPath path;
    path.addRoundedRect(rect, kHeight / 2, kHeight / 2);
    if (colors.fill.isValid()) {
        painter->fillPath(path, colors.fill);
    }
    painter->setPen(QPen(colors.border, 1));
    painter->drawPath(path);

    painter->setPen(colors.text);
    painter->drawText(rect, Qt::AlignCenter, text);
    painter->restore();
}

PillColors PillPainter::colorsForRef(RefKind kind, bool isHead) {
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
        case RefKind::Note:
        case RefKind::Stash:
        case RefKind::Other:
        default:
            return {ThemeManager::color(Token::TextTertiary),
                    ThemeManager::color(Token::BorderDefault),
                    QColor()};
    }
}

}  // namespace gbm
