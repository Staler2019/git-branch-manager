#pragma once

#include <QString>

namespace gbm {

/// Launches the platform's terminal application rooted at `path`.
///
/// There is no QDesktopServices equivalent for "open a terminal" the way
/// QDesktopServices::openUrl(QUrl::fromLocalFile(path)) opens a file manager
/// -- a terminal is not a file-association target, so this shells out to
/// QProcess::startDetached with a per-platform launcher command instead.
/// Returns false (with `error` set, if non-null) when every candidate
/// launcher on this platform failed to start.
bool openTerminalAt(const QString& path, QString* error = nullptr);

}  // namespace gbm
