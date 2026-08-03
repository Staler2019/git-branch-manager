#include "app/views/OperationLogView.h"

#include "app/bridge/ThemeManager.h"

#include <QApplication>
#include <QClipboard>
#include <QDateTime>
#include <QHBoxLayout>
#include <QMetaObject>
#include <QPushButton>
#include <QVBoxLayout>

namespace gbm {

OperationLogView::OperationLogView(QWidget* parent) : QWidget(parent) {
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);

    text_ = new QPlainTextEdit(this);
    text_->setReadOnly(true);
    text_->setMaximumBlockCount(kMaxBlocks);
    // ThemeManager::monoFont() (not QFontDatabase::systemFont) so the log
    // shows the bundled JetBrains Mono instead of whatever fixed-width font
    // the platform happens to default to.
    text_->setFont(ThemeManager::monoFont(12));
    text_->setLineWrapMode(QPlainTextEdit::NoWrap);
    text_->setPlaceholderText(QStringLiteral("Git commands run by this session appear here"));
    text_->setAccessibleName(QStringLiteral("Operation log"));

    auto* buttons = new QHBoxLayout;
    auto* copyButton = new QPushButton(QStringLiteral("Copy all"), this);
    auto* clearButton = new QPushButton(QStringLiteral("Clear"), this);
    copyButton->setAccessibleName(QStringLiteral("Copy operation log"));
    clearButton->setAccessibleName(QStringLiteral("Clear operation log"));
    buttons->addWidget(copyButton);
    buttons->addWidget(clearButton);
    buttons->addStretch(1);

    layout->addWidget(text_, 1);
    layout->addLayout(buttons);

    connect(copyButton, &QPushButton::clicked, this, &OperationLogView::copyAllToClipboard);
    connect(clearButton, &QPushButton::clicked, this, &OperationLogView::clearLog);

    // Records originate on worker threads; the queued connection is what makes
    // touching the widget safe.
    connect(this,
            &OperationLogView::recordArrived,
            this,
            &OperationLogView::appendRecord,
            Qt::QueuedConnection);
}

void OperationLogView::installAsSink() {
    Log::instance().setOperationSink(
        [this](const OperationRecord& record) { emit recordArrived(record); });
    Log::instance().setMessageSink([this](LogLevel level, std::string_view message) {
        const QString text = QString::fromUtf8(message.data(), static_cast<int>(message.size()));
        QMetaObject::invokeMethod(
            this,
            [this, level, text] { appendMessage(static_cast<int>(level), text); },
            Qt::QueuedConnection);
    });
}

void OperationLogView::appendRecord(const OperationRecord& record) {
    const QString when =
        QDateTime::fromSecsSinceEpoch(
            std::chrono::duration_cast<std::chrono::seconds>(record.when.time_since_epoch())
                .count())
            .toString(QStringLiteral("HH:mm:ss"));

    QString line =
        QStringLiteral("[%1] git %2").arg(when, QString::fromStdString(record.commandLine()));
    if (!record.repoDir.empty()) {
        line += QStringLiteral("\n         in %1").arg(QString::fromStdString(record.repoDir));
    }
    line +=
        QStringLiteral("\n         exit %1 in %2 ms").arg(record.exitCode).arg(record.durationMs);
    if (record.cancelled) {
        line += QStringLiteral(" (cancelled)");
    }
    if (record.timedOut) {
        line += QStringLiteral(" (timed out)");
    }
    // stderr verbatim: summarising it here would defeat the point of the panel.
    if (!record.stderrText.empty()) {
        line += QStringLiteral("\n         ") +
                QString::fromStdString(record.stderrText)
                    .trimmed()
                    .replace(QLatin1Char('\n'), QStringLiteral("\n         "));
    }

    text_->appendPlainText(line);
}

void OperationLogView::appendMessage(int level, const QString& message) {
    const auto logLevel = static_cast<LogLevel>(level);
    const QString prefix =
        QString::fromUtf8(toString(logLevel).data(), static_cast<int>(toString(logLevel).size()));
    text_->appendPlainText(QStringLiteral("[%1] %2").arg(prefix, message));
}

void OperationLogView::copyAllToClipboard() {
    QApplication::clipboard()->setText(text_->toPlainText());
}

void OperationLogView::clearLog() {
    text_->clear();
}

}  // namespace gbm
