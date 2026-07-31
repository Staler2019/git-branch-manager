#include "gbm/Version.h"

#include "app/views/MainWindow.h"
#include "core/base/Logging.h"
#include "core/base/ThreadCheck.h"
#include "core/git/AskpassHelper.h"
#include "core/git/GitExecutable.h"

#include <QApplication>
#include <QMessageBox>
#include <QStandardPaths>
#include <QTimer>

#include <cstdlib>
#include <string_view>

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

    return QApplication::exec();
}
