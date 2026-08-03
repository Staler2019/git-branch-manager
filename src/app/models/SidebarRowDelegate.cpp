#include "app/models/SidebarRowDelegate.h"

#include "app/bridge/ThemeManager.h"
#include "app/models/PillPainter.h"
#include "app/models/RepoListModel.h"
#include "app/theme/IconLoader.h"
#include "core/discovery/RepoClassifier.h"

#include <QFontMetrics>
#include <QIcon>
#include <QPainter>
#include <QPainterPath>
#include <QStringList>
#include <QStyle>

#include <algorithm>

namespace gbm {

namespace {

constexpr int kIconSize = 16;
constexpr int kInset = 4;  // Inset selection/hover background from the row edge.
constexpr int kRadius = 6;
constexpr int kBadgeFontSize = 11;

QString repoIconName(int kindValue) {
    switch (static_cast<RepoKind>(kindValue)) {
        case RepoKind::LinkedWorktree:
        case RepoKind::Submodule:
            return QStringLiteral("git-fork");
        case RepoKind::Bare:
        case RepoKind::Normal:
        case RepoKind::NotARepo:
        default:
            return QStringLiteral("git-branch");
    }
}

}  // namespace

SidebarRowDelegate::SidebarRowDelegate(Kind kind, QObject* parent)
    : QStyledItemDelegate(parent), kind_(kind) {}

QSize SidebarRowDelegate::sizeHint(const QStyleOptionViewItem& option,
                                   const QModelIndex& index) const {
    QSize size = QStyledItemDelegate::sizeHint(option, index);
    size.setHeight(std::max(size.height(), ThemeManager::rowHeight()));
    return size;
}

void SidebarRowDelegate::paint(QPainter* painter,
                               const QStyleOptionViewItem& option,
                               const QModelIndex& index) const {
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);

    const QRect insetRect = option.rect.adjusted(kInset, 2, -kInset, -2);
    if (option.state & QStyle::State_Selected) {
        QPainterPath path;
        path.addRoundedRect(insetRect, kRadius, kRadius);
        painter->fillPath(path, ThemeManager::color(Token::SurfaceSelected));
    } else if (option.state & QStyle::State_MouseOver) {
        QPainterPath path;
        path.addRoundedRect(insetRect, kRadius, kRadius);
        painter->fillPath(path, ThemeManager::color(Token::SurfaceHover));
    }

    const QString iconName = kind_ == Kind::Repository
                                 ? repoIconName(index.data(RepoListModel::KindRole).toInt())
                                 : QStringLiteral("archive");
    const QIcon icon = IconLoader::icon(iconName, Token::TextSecondary, kIconSize);

    QRect iconRect(insetRect.left() + 6,
                   insetRect.top() + (insetRect.height() - kIconSize) / 2,
                   kIconSize,
                   kIconSize);
    icon.paint(painter, iconRect);

    const int textLeft = iconRect.right() + 8;
    QFont textFont = ThemeManager::uiFont(13);
    painter->setFont(textFont);
    painter->setPen(ThemeManager::color(Token::TextPrimary));
    const QFontMetrics textMetrics(textFont);

    int badgeWidth = 0;
    QString badgeText;
    if (kind_ == Kind::Repository) {
        const int ahead = index.data(RepoListModel::AheadRole).toInt();
        const int behind = index.data(RepoListModel::BehindRole).toInt();
        QStringList parts;
        if (ahead > 0) {
            parts << QStringLiteral("↑%1").arg(ahead);
        }
        if (behind > 0) {
            parts << QStringLiteral("↓%1").arg(behind);
        }
        badgeText = parts.join(QStringLiteral(" "));
    }

    const QFont badgeFont = ThemeManager::monoFont(kBadgeFontSize);
    if (!badgeText.isEmpty()) {
        const QFontMetrics badgeMetrics(badgeFont);
        badgeWidth = PillPainter::widthFor(badgeText, badgeMetrics) + 6;
    }

    const QRect textRect(textLeft,
                         insetRect.top(),
                         std::max(insetRect.right() - 6 - badgeWidth - textLeft, 0),
                         insetRect.height());
    const QString elided = textMetrics.elidedText(
        index.data(Qt::DisplayRole).toString(), Qt::ElideMiddle, textRect.width());
    painter->drawText(textRect, Qt::AlignVCenter | Qt::AlignLeft, elided);

    if (!badgeText.isEmpty()) {
        const int badgePillWidth = badgeWidth - 6;
        const QRect badgeRect(insetRect.right() - 6 - badgePillWidth,
                              insetRect.top() + (insetRect.height() - PillPainter::kHeight) / 2,
                              badgePillWidth,
                              PillPainter::kHeight);
        const PillColors colors{ThemeManager::color(Token::TextSecondary),
                                ThemeManager::color(Token::SurfaceSunken),
                                ThemeManager::color(Token::SurfaceSunken)};
        PillPainter::paint(painter, badgeRect, badgeText, badgeFont, colors);
    }

    painter->restore();
}

}  // namespace gbm
