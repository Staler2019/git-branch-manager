// Tests for the theme foundation: the token table, the QSS placeholder
// substitution, the persisted settings (theme + density) including the
// legacy `Theme` (System/Light/Dark) -> `ThemeId` migration, and finally
// `ThemeManager::apply()` itself. Most of this is pure logic reachable
// without a live QApplication style change -- `ThemeManager::applyTokensToQss`
// is factored out of `apply()` specifically so substitution is testable on
// its own -- but `QTEST_MAIN` here links Widgets and so does construct a
// real (offscreen) `QApplication`, which the last slot uses to prove `apply()`
// actually pushes a theme-specific stylesheet and palette.
#include "app/bridge/ThemeManager.h"
#include "app/theme/IconLoader.h"
#include "app/theme/Metrics.h"
#include "app/theme/ThemeTokens.h"
#include "app/theme/Tokens.h"

#include <QApplication>
#include <QFile>
#include <QImage>
#include <QRegularExpression>
#include <QSettings>
#include <QTemporaryDir>
#include <QTextStream>
#include <QtTest>

using namespace gbm;

namespace {

constexpr std::array<Token, 39> kAllTokens{
    Token::SurfaceApp,     Token::SurfacePanel,  Token::SurfacePanelRaised,
    Token::SurfaceSunken,  Token::SurfaceHover,  Token::SurfaceSelected,
    Token::SurfaceOverlay, Token::BorderSubtle,  Token::BorderDefault,
    Token::BorderStrong,   Token::BorderFocus,   Token::TextPrimary,
    Token::TextSecondary,  Token::TextTertiary,  Token::TextOnAccent,
    Token::TextLink,       Token::Accent,        Token::AccentHover,
    Token::AccentActive,   Token::AccentSubtle,  Token::RefChipFill,
    Token::RefChipText,    Token::Success,       Token::Danger,
    Token::DangerHover,    Token::Warning,       Token::DiffAddBg,
    Token::DiffAddText,    Token::DiffDelBg,     Token::DiffDelText,
    Token::DiffAddStrong,  Token::DiffDelStrong, Token::ScrollbarThumb,
    Token::GraphLane1,     Token::GraphLane2,    Token::GraphLane3,
    Token::GraphLane4,     Token::GraphLane5,    Token::GraphLane6,
};

constexpr std::array<ThemeId, 3> kAllThemes{
    ThemeId::DarkTechnical,
    ThemeId::LightIde,
    ThemeId::NeutralProfessional,
};

}  // namespace

class ThemeTest : public QObject {
    Q_OBJECT

private slots:

    void initTestCase() {
        // Redirect QSettings to a scratch file for the whole test run, so
        // this never touches (or is polluted by) the real application's
        // saved preferences.
        tempDir_ = std::make_unique<QTemporaryDir>();
        QVERIFY(tempDir_->isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, tempDir_->path());
        QCoreApplication::setOrganizationName(QStringLiteral("git-branch-manager"));
        QCoreApplication::setApplicationName(QStringLiteral("git-branch-manager"));
    }

    void init() {
        QSettings settings;
        settings.clear();
    }

    // Every Token resolves to a valid (non-default-constructed) QColor for
    // all three themes -- no gaps in the table.
    void everyTokenResolvesInEveryTheme() {
        for (ThemeId theme : kAllThemes) {
            for (Token token : kAllTokens) {
                const QColor color = tokenColor(theme, token);
                QVERIFY2(color.isValid(),
                         qPrintable(QStringLiteral("theme %1 token %2 did not resolve")
                                        .arg(static_cast<int>(theme))
                                        .arg(static_cast<int>(token))));
            }
        }
    }

    // QSS template substitution leaves no unresolved `@` placeholder, for any
    // theme -- proves the placeholder table in ThemeManager.cpp covers every
    // token app.qss actually uses.
    void qssSubstitutionLeavesNoUnresolvedPlaceholder() {
        QFile qssFile(QStringLiteral(":/qss/app.qss"));
        QVERIFY(qssFile.open(QIODevice::ReadOnly | QIODevice::Text));
        QTextStream stream(&qssFile);
        const QString qssTemplate = stream.readAll();
        QVERIFY(!qssTemplate.isEmpty());

        // A mis-ordered placeholder table (a shorter name listed before a
        // longer one that starts with it, e.g. `@accent` before
        // `@accent-hover`) would not leave an unresolved `@` -- it would eat
        // the prefix and leave a mangled hex colour with a stray suffix
        // instead, silently accepted by Qt. Guard against both failure modes.
        static const QRegularExpression kMangledHex(QStringLiteral("#[0-9a-fA-F]{6}[a-zA-Z-]"));

        for (ThemeId theme : kAllThemes) {
            const QString substituted = ThemeManager::applyTokensToQss(qssTemplate, theme);
            QVERIFY2(!substituted.contains(QLatin1Char('@')),
                     qPrintable(QStringLiteral("theme %1 left an unresolved @ placeholder")
                                    .arg(static_cast<int>(theme))));
            QVERIFY2(!substituted.contains(kMangledHex),
                     qPrintable(QStringLiteral("theme %1 produced a mangled hex colour "
                                               "(placeholder table mis-ordered?)")
                                    .arg(static_cast<int>(theme))));
        }
    }

    // The bundled font resources referenced by ThemeManager::ensureFontsRegistered
    // actually exist in the .qrc -- a typo there would otherwise stay invisible
    // until a later phase calls uiFont()/monoFont() for the first time.
    void bundledFontResourcesExist() {
        for (const char* resource : {":/fonts/Inter-Regular.ttf",
                                     ":/fonts/Inter-Medium.ttf",
                                     ":/fonts/Inter-SemiBold.ttf",
                                     ":/fonts/Inter-Bold.ttf",
                                     ":/fonts/JetBrainsMono-Regular.ttf",
                                     ":/fonts/JetBrainsMono-Medium.ttf"}) {
            QVERIFY2(QFile::exists(QLatin1String(resource)), resource);
        }
    }

    // rowHeight() follows the density setting.
    void rowHeightFollowsDensity() {
        ThemeManager::saveDensitySetting(Density::Comfortable);
        QCOMPARE(ThemeManager::loadDensitySetting(), Density::Comfortable);
        QCOMPARE(ThemeManager::rowHeight(), kRowHeightComfortable);

        ThemeManager::saveDensitySetting(Density::Compact);
        QCOMPARE(ThemeManager::loadDensitySetting(), Density::Compact);
        QCOMPARE(ThemeManager::rowHeight(), kRowHeightCompact);
    }

    // loadSetting() migrates the legacy 0/1/2 (System/Light/Dark) values:
    // System and Dark both become DarkTechnical, Light becomes LightIde.
    void loadSettingMigratesLegacyValues() {
        QSettings settings;

        settings.setValue(QStringLiteral("appearance/theme"), 0);  // legacy System
        QCOMPARE(ThemeManager::loadSetting(), ThemeId::DarkTechnical);

        settings.setValue(QStringLiteral("appearance/theme"), 1);  // legacy Light
        QCOMPARE(ThemeManager::loadSetting(), ThemeId::LightIde);

        settings.setValue(QStringLiteral("appearance/theme"), 2);  // legacy Dark
        QCOMPARE(ThemeManager::loadSetting(), ThemeId::DarkTechnical);

        settings.remove(QStringLiteral("appearance/theme"));  // unset -> default
        QCOMPARE(ThemeManager::loadSetting(), ThemeId::DarkTechnical);
    }

    void saveAndLoadSettingRoundTrips() {
        for (ThemeId theme : kAllThemes) {
            ThemeManager::saveSetting(theme);
            QCOMPARE(ThemeManager::loadSetting(), theme);
        }
    }

    // apply() itself: registers fonts, sets Fusion, builds the palette, and
    // actually pushes a theme-specific stylesheet onto the QApplication --
    // the composition applyTokensToQss() alone does not exercise. This is a
    // headless proxy for "visibly re-colors": it proves the mechanism, not
    // that a human eyeballed the three themes on screen. Runs last since it
    // mutates global QApplication state that later slots would otherwise see.
    void applyPushesATotallyDifferentStyleSheetPerTheme() {
        ThemeManager::apply(ThemeId::DarkTechnical);
        const QString dark = qApp->styleSheet();
        QVERIFY(!dark.isEmpty());
        QVERIFY(dark.contains(QStringLiteral("#0d1117")));  // dark-technical surface-app
        QCOMPARE(QApplication::palette().color(QPalette::Window),
                 ThemeManager::color(ThemeId::DarkTechnical, Token::SurfaceApp));

        ThemeManager::apply(ThemeId::LightIde);
        const QString light = qApp->styleSheet();
        QVERIFY(!light.isEmpty());
        QVERIFY(light != dark);
        QVERIFY(light.contains(QStringLiteral("#f5f6f8")));  // light-ide surface-sunken
        QCOMPARE(QApplication::palette().color(QPalette::Window),
                 ThemeManager::color(ThemeId::LightIde, Token::SurfaceApp));
    }

    // IconLoader's whole job is recoloring an SVG whose stroke was baked to
    // a literal opaque colour (never `currentColor` -- Qt's SVG renderer does
    // not resolve it) by recompositing with SourceIn. Before the app.qrc
    // AUTORCC fix, `QSvgRenderer::isValid()` would have been false here and
    // this would have silently produced a fully transparent icon -- exactly
    // the failure class that fix addresses, so this is the regression guard
    // for it on the icon-loading path specifically.
    void iconLoaderProducesANonTransparentPixmap() {
        ThemeManager::apply(ThemeId::DarkTechnical);
        const QIcon icon = IconLoader::icon(QStringLiteral("git-branch"), Token::TextPrimary, 16);
        QVERIFY(!icon.isNull());

        const QPixmap pixmap = icon.pixmap(16, 16);
        QVERIFY(!pixmap.isNull());
        const QImage image = pixmap.toImage();

        bool foundOpaquePixel = false;
        for (int y = 0; y < image.height() && !foundOpaquePixel; ++y) {
            for (int x = 0; x < image.width(); ++x) {
                if (qAlpha(image.pixel(x, y)) > 0) {
                    foundOpaquePixel = true;
                    break;
                }
            }
        }
        QVERIFY2(foundOpaquePixel, "IconLoader produced a fully transparent pixmap");
    }

private:
    std::unique_ptr<QTemporaryDir> tempDir_;
};

QTEST_MAIN(ThemeTest)
#include "ThemeTest.moc"
