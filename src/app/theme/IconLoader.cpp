#include "app/theme/IconLoader.h"

#include "app/bridge/ThemeManager.h"

#include <QGuiApplication>
#include <QHash>
#include <QPainter>
#include <QPixmap>
#include <QScreen>
#include <QSvgRenderer>

namespace gbm {

namespace {

QHash<QString, QIcon>& cache() {
    static QHash<QString, QIcon> table;
    return table;
}

QString cacheKeyFor(const QString& name, Token token, int pixelSize, qreal dpr) {
    return QStringLiteral("%1|%2|%3|%4")
        .arg(name)
        .arg(static_cast<int>(token))
        .arg(pixelSize)
        .arg(dpr, 0, 'f', 2);
}

}  // namespace

QIcon IconLoader::icon(const QString& name, Token token, int pixelSize) {
    const qreal dpr =
        QGuiApplication::primaryScreen() ? QGuiApplication::primaryScreen()->devicePixelRatio() : 1.0;
    const QString key = cacheKeyFor(name, token, pixelSize, dpr);
    if (const auto it = cache().constFind(key); it != cache().constEnd()) {
        return it.value();
    }

    QSvgRenderer renderer(QStringLiteral(":/icons/%1.svg").arg(name));
    const int device = qRound(pixelSize * dpr);
    QPixmap pixmap(device, device);
    pixmap.fill(Qt::transparent);

    if (renderer.isValid()) {
        QPainter painter(&pixmap);
        painter.setRenderHint(QPainter::Antialiasing, true);
        renderer.render(&painter, QRectF(0, 0, device, device));
        painter.end();

        // Discards the SVG's baked stroke colour (never `currentColor` --
        // see THIRD_PARTY_NOTICES.md) and repaints the shape's alpha
        // uniformly with the theme colour.
        QPainter tintPainter(&pixmap);
        tintPainter.setCompositionMode(QPainter::CompositionMode_SourceIn);
        tintPainter.fillRect(pixmap.rect(), ThemeManager::color(token));
        tintPainter.end();
    }
    pixmap.setDevicePixelRatio(dpr);

    const QIcon result(pixmap);
    cache().insert(key, result);
    return result;
}

void IconLoader::clearCache() {
    cache().clear();
}

}  // namespace gbm
