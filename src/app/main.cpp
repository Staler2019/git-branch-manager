#include "gbm/Version.h"

#include "app/bridge/ThemeManager.h"
#include "app/views/MainWindow.h"
#include "core/base/Logging.h"
#include "core/base/ThreadCheck.h"
#include "core/git/AskpassHelper.h"
#include "core/git/GitExecutable.h"

#include <QApplication>
#include <QByteArray>
#include <QMessageBox>
#include <QStandardPaths>
#include <QTimer>

#include <cstdlib>
#include <string_view>

namespace {

/// Deterministic visual-verification seam (see the plan's Verification
/// section): with `GBM_SCREENSHOT` set, grabs the window and quits once it
/// has settled. `GBM_SCREENSHOT_REPO`, if also set, opens that path first --
/// `stack_` otherwise starts on the repository browser page, not the
/// repository shell the design describes. Neither variable does anything in
/// a normal run.
void armScreenshotHook(gbm::MainWindow& window) {
    const char* screenshotPath = std::getenv("GBM_SCREENSHOT");
    if (screenshotPath == nullptr) {
        return;
    }
    const QString path = QString::fromUtf8(screenshotPath);

    // The design (Design.pdf) is the dark-technical variant, so that's the
    // default here regardless of whatever theme this machine's QSettings
    // happens to have persisted -- comparison screenshots are never
    // accidentally taken against light-ide/neutral-professional unless asked
    // for via GBM_SCREENSHOT_THEME (used to spot-check that the other two
    // themes stay coherent after a token/QSS change). The prior setting is
    // restored after capture (apply() persists whatever it is given) so a
    // screenshot run never leaves a developer's or CI machine's saved
    // preference changed.
    gbm::ThemeId shotTheme = gbm::ThemeId::DarkTechnical;
    if (const char* themeEnv = std::getenv("GBM_SCREENSHOT_THEME"); themeEnv != nullptr) {
        const std::string_view themeName(themeEnv);
        if (themeName == "light") {
            shotTheme = gbm::ThemeId::LightIde;
        } else if (themeName == "neutral") {
            shotTheme = gbm::ThemeId::NeutralProfessional;
        }
    }
    const gbm::ThemeId previousTheme = gbm::ThemeManager::loadSetting();
    gbm::ThemeManager::apply(shotTheme);

    auto capture = [&window, path, previousTheme] {
        // GBM_SCREENSHOT_SWITCH_THEME_AFTER exercises the *runtime* theme
        // switch path (MainWindow::applyThemeAndRefresh, wired to the
        // toolbar/menu theme actions) rather than just starting the process
        // already on a given theme (which is all shotTheme above does) --
        // the two are different code paths, and only the former re-bakes
        // icons that were set once at buildMenus() time (title bar, Fetch/
        // Pull/Push, Refresh, the palette icons).
        if (const char* switchEnv = std::getenv("GBM_SCREENSHOT_SWITCH_THEME_AFTER");
            switchEnv != nullptr) {
            const std::string_view name(switchEnv);
            if (name == "light") {
                window.switchThemeForScreenshot(gbm::ThemeId::LightIde);
            } else if (name == "neutral") {
                window.switchThemeForScreenshot(gbm::ThemeId::NeutralProfessional);
            } else if (name == "dark") {
                window.switchThemeForScreenshot(gbm::ThemeId::DarkTechnical);
            }
        }
        // One more event-loop turn so QSS polish and the first real paint
        // (not just the first show event) have both landed.
        QTimer::singleShot(200, &window, [&window, path, previousTheme] {
            const QPixmap grab = window.grab();
            grab.save(path);
            gbm::ThemeManager::saveSetting(previousTheme);
            QApplication::quit();
        });
    };

    if (const char* repoPath = std::getenv("GBM_SCREENSHOT_REPO"); repoPath != nullptr) {
        // Deferred past loadInitialState (itself queued via singleShot(0) in
        // main()), so the cache is open and the window has done its first
        // real layout before a repository is force-opened into it.
        QTimer::singleShot(50, &window, [&window, repoPath, capture] {
            window.openRepositoryAtPathForScreenshot(QString::fromUtf8(repoPath));

            const char* expandEnv = std::getenv("GBM_SCREENSHOT_EXPAND_ROW");
            const char* selectEnv = std::getenv("GBM_SCREENSHOT_SELECT_ROW");
            if (expandEnv != nullptr || selectEnv != nullptr) {
                bool ok = false;
                const int row = QByteArray(expandEnv != nullptr ? expandEnv : selectEnv).toInt(&ok);
                const bool expand = expandEnv != nullptr;
                // A longer delay than the plain-open case: both need the
                // repository's history walk (refreshHistory, itself posted
                // async from openRepository) to have produced rows first, and
                // expanding additionally needs commit-details' own async
                // git-process read to land before the panel has real content
                // to show instead of "Loading changes…".
                QTimer::singleShot(600, &window, [&window, row, ok, expand] {
                    if (!ok) {
                        return;
                    }
                    if (expand) {
                        window.expandCommitRowForScreenshot(row);
                    } else {
                        window.selectCommitRowForScreenshot(row);
                    }
                });
                QTimer::singleShot(1200, &window, capture);
                return;
            }
            capture();
        });
    } else {
        capture();
    }
}

}  // namespace

int main(int argc, char** argv) {
    // The askpass handshake re-invokes this same executable (see
    // AskpassHelper::wire): GIT_ASKPASS points back at us, and git calls it as
    // a plain synchronous child expecting a line of output on stdout. That
    // child must never touch Qt or open a window -- it runs headless, often
    // while the real GUI process is itself blocked waiting for the git command
    // that spawned it, so this has to be handled before QApplication exists.
    if (const char* askpassMode = std::getenv("GBM_ASKPASS_MODE");
        askpassMode != nullptr && std::string_view(askpassMode) == "1") {
        return gbm::askpass::runClient(argc, argv);
    }

    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("git-branch-manager"));
    QApplication::setOrganizationName(QStringLiteral("git-branch-manager"));
    QApplication::setApplicationVersion(QStringLiteral(GBM_VERSION_STRING));

    // Before the window is built, so the very first paint already reflects
    // the saved choice instead of flashing the default theme first.
    gbm::ThemeManager::apply(gbm::ThemeManager::loadSetting());

    gbm::Log::instance().setLevel(gbm::LogLevel::Info);

    // Git is detected, never bundled. If it is missing or too old, say so plainly
    // and point at the fix rather than failing later with a confusing git error.
    //
    // This runs before the UI thread is registered, and deliberately so: detection
    // spawns `git --version`, which the not-on-UI-thread assertion would otherwise
    // (correctly) reject. It is a single ~10 ms call during bootstrap, before any
    // window exists, so there is no responsiveness to protect yet — and the result
    // is needed to construct the window at all.
    auto installation = gbm::GitExecutable::detect();
    if (!installation) {
        QMessageBox box;
        box.setIcon(QMessageBox::Critical);
        box.setWindowTitle(QStringLiteral("Git is required"));
        box.setText(
            QStringLiteral("git-branch-manager needs Git %1 or newer, but none was "
                           "found on this system.")
                .arg(QString::fromStdString(gbm::GitInstallation::minimumSupported().toString())));
        box.setInformativeText(
            QStringLiteral("Install Git from https://git-scm.com/downloads and start the "
                           "application again.\n\nIf Git is installed somewhere unusual, set its "
                           "location in Settings."));
        box.setDetailedText(QString::fromStdString(installation.error().detail.empty()
                                                       ? installation.error().message
                                                       : installation.error().detail));
        box.exec();
        return 1;
    }

    // From here on the UI thread is live, so core entry points that spawn a process
    // assert they are never called on it. This one line is what keeps the "UI thread
    // does no process work" invariant enforceable rather than aspirational.
    gbm::UiThread::markCurrentAsUi();

    gbm::MainWindow window(*installation);
    window.show();

    // Deliberately after show(): the window paints before any repository work
    // begins, and the cached list is then loaded from SQLite with no filesystem
    // access. Doing this before show() is exactly the slow startup we avoid.
    QTimer::singleShot(0, &window, [&window] { window.loadInitialState(); });

    armScreenshotHook(window);

    return QApplication::exec();
}
