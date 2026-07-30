#pragma once

#include "core/base/Logging.h"

#include <QPlainTextEdit>
#include <QWidget>

namespace gbm {

/// Shows every git invocation: argv, duration, exit code and full stderr.
///
/// Not a debug nicety. Because the entire backend is the git CLI, this panel is
/// the difference between a bug report someone can act on and guesswork — the user
/// can copy the exact command and run it themselves. It also means an error message
/// never has to be the only evidence of what happened.
class OperationLogView : public QWidget {
    Q_OBJECT

public:
    explicit OperationLogView(QWidget* parent = nullptr);

    /// Installs this view as the process-wide operation sink. Records arrive from
    /// worker threads, so this marshals them onto the UI thread.
    void installAsSink();

public slots:
    void appendRecord(const OperationRecord& record);
    void appendMessage(int level, const QString& message);
    void copyAllToClipboard();
    void clearLog();

signals:
    void recordArrived(const OperationRecord& record);

private:
    /// Bounded so a long session cannot grow without limit; git output on a large
    /// repository is voluminous.
    static constexpr int kMaxBlocks = 5000;

    QPlainTextEdit* text_;
};

}  // namespace gbm
