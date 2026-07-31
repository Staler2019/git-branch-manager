#include "app/bridge/ThemeManager.h"

#include <QApplication>
#include <QSettings>
#include <QStyle>
#include <QStyleFactory>

namespace gbm {

namespace {

constexpr auto kSettingsKey = "appearance/theme";

/// Remembered so `Light`/`Dark` can be re-applied (e.g. after a QSettings
/// change elsewhere) without needing to rebuild the style name from scratch,
/// and so `System` has something concrete to restore.
QString defaultStyleName() {
    static const QString name =
        QApplication::style() != nullptr ? QApplication::style()->objectName() : QString();
    return name;
}

}  // namespace

Theme ThemeManager::loadSetting() {
    QSettings settings;
    const int stored = settings.value(QLatin1String(kSettingsKey), 0).toInt();
    switch (stored) {
        case 1:
            return Theme::Light;
        case 2:
            return Theme::Dark;
        default:
            return Theme::System;
    }
}

void ThemeManager::saveSetting(Theme theme) {
    QSettings settings;
    settings.setValue(QLatin1String(kSettingsKey),
                      theme == Theme::Light  ? 1
                      : theme == Theme::Dark ? 2
                                             : 0);
}

QPalette ThemeManager::lightPalette() {
    QPalette palette;
    palette.setColor(QPalette::Window, QColor(240, 240, 240));
    palette.setColor(QPalette::WindowText, Qt::black);
    palette.setColor(QPalette::Base, Qt::white);
    palette.setColor(QPalette::AlternateBase, QColor(233, 233, 233));
    palette.setColor(QPalette::ToolTipBase, Qt::white);
    palette.setColor(QPalette::ToolTipText, Qt::black);
    palette.setColor(QPalette::Text, Qt::black);
    palette.setColor(QPalette::Button, QColor(240, 240, 240));
    palette.setColor(QPalette::ButtonText, Qt::black);
    palette.setColor(QPalette::BrightText, Qt::red);
    palette.setColor(QPalette::Link, QColor(0, 102, 204));
    palette.setColor(QPalette::Highlight, QColor(76, 163, 224));
    palette.setColor(QPalette::HighlightedText, Qt::white);
    palette.setColor(QPalette::Disabled, QPalette::Text, QColor(150, 150, 150));
    palette.setColor(QPalette::Disabled, QPalette::WindowText, QColor(150, 150, 150));
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(150, 150, 150));
    return palette;
}

QPalette ThemeManager::darkPalette() {
    // The long-published "Fusion dark palette" recipe (Qt's own examples and
    // documentation use these exact values), because it is a known-legible
    // starting point rather than a guess at contrast ratios.
    QPalette palette;
    palette.setColor(QPalette::Window, QColor(53, 53, 53));
    palette.setColor(QPalette::WindowText, Qt::white);
    palette.setColor(QPalette::Base, QColor(35, 35, 35));
    palette.setColor(QPalette::AlternateBase, QColor(53, 53, 53));
    palette.setColor(QPalette::ToolTipBase, Qt::white);
    palette.setColor(QPalette::ToolTipText, Qt::white);
    palette.setColor(QPalette::Text, Qt::white);
    palette.setColor(QPalette::Button, QColor(53, 53, 53));
    palette.setColor(QPalette::ButtonText, Qt::white);
    palette.setColor(QPalette::BrightText, Qt::red);
    palette.setColor(QPalette::Link, QColor(42, 130, 218));
    palette.setColor(QPalette::Highlight, QColor(42, 130, 218));
    palette.setColor(QPalette::HighlightedText, Qt::black);
    palette.setColor(QPalette::Disabled, QPalette::Text, QColor(127, 127, 127));
    palette.setColor(QPalette::Disabled, QPalette::WindowText, QColor(127, 127, 127));
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(127, 127, 127));
    return palette;
}

void ThemeManager::apply(Theme theme) {
    defaultStyleName();  // captured on first call, before anything below changes it.

    switch (theme) {
        case Theme::System:
            if (QStyle* style = QStyleFactory::create(defaultStyleName()); style != nullptr) {
                QApplication::setStyle(style);
            }
            QApplication::setPalette(QApplication::style()->standardPalette());
            break;
        case Theme::Light:
            QApplication::setStyle(QStyleFactory::create(QStringLiteral("Fusion")));
            QApplication::setPalette(lightPalette());
            break;
        case Theme::Dark:
            QApplication::setStyle(QStyleFactory::create(QStringLiteral("Fusion")));
            QApplication::setPalette(darkPalette());
            break;
    }
}

QString ThemeManager::label(Theme theme) {
    switch (theme) {
        case Theme::System:
            return QStringLiteral("System");
        case Theme::Light:
            return QStringLiteral("Light");
        case Theme::Dark:
            return QStringLiteral("Dark");
    }
    return QStringLiteral("System");
}

}  // namespace gbm
