#include "app/views/TerminalLauncher.h"

#include <QProcess>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QStringList>

namespace gbm {

namespace {

#if defined(Q_OS_MACOS)

bool launchMacTerminal(const QString& path, QString* error) {
    // `open -a Terminal <path>` opens (or focuses) Terminal.app with a new
    // window/tab rooted at `path`, the same mechanism QDesktopServices uses
    // internally for file-manager opens elsewhere in this codebase.
    if (QProcess::startDetached(QStringLiteral("open"),
                                {QStringLiteral("-a"), QStringLiteral("Terminal"), path})) {
        return true;
    }
    if (error != nullptr) {
        *error = QStringLiteral("Could not launch Terminal.app");
    }
    return false;
}

#elif defined(Q_OS_WIN)

bool launchWindowsTerminal(const QString& path, QString* error) {
    // Windows Terminal first (ships with modern Windows and is the better
    // experience); cmd.exe's own `start` as a universally-available fallback.
    if (QProcess::startDetached(QStringLiteral("wt.exe"), {QStringLiteral("-d"), path})) {
        return true;
    }
    if (QProcess::startDetached(QStringLiteral("cmd.exe"),
                                {QStringLiteral("/c"),
                                 QStringLiteral("start"),
                                 QStringLiteral(""),
                                 QStringLiteral("/d"),
                                 path,
                                 QStringLiteral("cmd.exe")})) {
        return true;
    }
    if (error != nullptr) {
        *error = QStringLiteral("Could not launch a terminal (tried Windows Terminal and cmd.exe)");
    }
    return false;
}

#else

bool launchLinuxTerminal(const QString& path, QString* error) {
    // $TERMINAL is the closest thing Linux desktops have to a standard --
    // honor it first, then fall back to whichever common emulator is
    // actually installed, checked in roughly most-to-least-likely order.
    const QString envTerminal =
        QProcessEnvironment::systemEnvironment().value(QStringLiteral("TERMINAL"));
    QStringList candidates;
    if (!envTerminal.isEmpty()) {
        candidates.append(envTerminal);
    }
    candidates += {QStringLiteral("x-terminal-emulator"),
                   QStringLiteral("gnome-terminal"),
                   QStringLiteral("konsole"),
                   QStringLiteral("xterm")};

    for (const QString& candidate : candidates) {
        const QString resolved = QStandardPaths::findExecutable(candidate);
        if (resolved.isEmpty()) {
            continue;
        }
        // Every candidate here accepts --working-directory except xterm,
        // which uses -e sh -c 'cd ... && exec $SHELL' instead; simplest
        // correct approach is to launch through the shell for all of them.
        const QString command =
            candidate == QStringLiteral("xterm")
                ? QStringLiteral("cd %1 && exec xterm").arg(path)
                : QStringLiteral("%1 --working-directory=%2").arg(candidate, path);
        if (QProcess::startDetached(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), command})) {
            return true;
        }
    }
    if (error != nullptr) {
        *error = QStringLiteral(
            "Could not find a terminal emulator. Set the $TERMINAL environment variable to "
            "your preferred one.");
    }
    return false;
}

#endif

}  // namespace

bool openTerminalAt(const QString& path, QString* error) {
#if defined(Q_OS_MACOS)
    return launchMacTerminal(path, error);
#elif defined(Q_OS_WIN)
    return launchWindowsTerminal(path, error);
#else
    return launchLinuxTerminal(path, error);
#endif
}

}  // namespace gbm
