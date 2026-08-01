#include "app/dialogs/LineHistoryDialog.h"

#include <QPlainTextEdit>
#include <QPushButton>
#include <QVBoxLayout>

namespace gbm {

LineHistoryDialog::LineHistoryDialog(const QString& path,
                                     const std::vector<LineHistoryChunk>& chunks,
                                     QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Line history: %1").arg(path));
    auto* layout = new QVBoxLayout(this);
    auto* text = new QPlainTextEdit(this);
    text->setReadOnly(true);
    text->setLineWrapMode(QPlainTextEdit::NoWrap);
    QString content;
    for (const LineHistoryChunk& chunk : chunks) {
        content += QStringLiteral("commit %1 — %2\n%3\n\n")
                       .arg(QString::fromStdString(chunk.oid.shortHex()))
                       .arg(QString::fromStdString(chunk.subject))
                       .arg(QString::fromStdString(chunk.diffText));
    }
    text->setPlainText(content);
    layout->addWidget(text);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);
    layout->addWidget(closeButton);
    resize(720, 480);
}

}  // namespace gbm
