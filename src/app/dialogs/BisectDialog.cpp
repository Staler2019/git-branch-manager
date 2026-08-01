#include "app/dialogs/BisectDialog.h"

#include "app/bridge/RepositorySession.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QVBoxLayout>

namespace gbm {

BisectDialog::BisectDialog(RepositorySession* session,
                           RunWithFeedbackFn runWithFeedback,
                           QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Bisect"));
    auto* layout = new QVBoxLayout(this);

    // --- "not bisecting yet" form ---
    auto* startForm = new QWidget(this);
    auto* startLayout = new QVBoxLayout(startForm);
    startLayout->setContentsMargins(0, 0, 0, 0);
    auto* badRow = new QHBoxLayout();
    auto* badLabel = new QLabel(QStringLiteral("Bad commit:"), startForm);
    auto* badEdit = new QLineEdit(QStringLiteral("HEAD"), startForm);
    badEdit->setAccessibleName(QStringLiteral("Bad commit"));
    badRow->addWidget(badLabel);
    badRow->addWidget(badEdit, 1);
    startLayout->addLayout(badRow);
    auto* goodRow = new QHBoxLayout();
    auto* goodLabel = new QLabel(QStringLiteral("Good commit:"), startForm);
    auto* goodEdit = new QLineEdit(startForm);
    goodEdit->setPlaceholderText(QStringLiteral("e.g. a tag, branch or commit known to work"));
    goodEdit->setAccessibleName(QStringLiteral("Good commit"));
    goodRow->addWidget(goodLabel);
    goodRow->addWidget(goodEdit, 1);
    startLayout->addLayout(goodRow);
    auto* startButton = new QPushButton(QStringLiteral("Start bisect"), startForm);
    startLayout->addWidget(startButton, 0, Qt::AlignRight);
    layout->addWidget(startForm);

    // --- "bisecting" status view ---
    auto* statusWidget = new QWidget(this);
    auto* statusLayout = new QVBoxLayout(statusWidget);
    statusLayout->setContentsMargins(0, 0, 0, 0);
    auto* currentLabel = new QLabel(statusWidget);
    currentLabel->setWordWrap(true);
    statusLayout->addWidget(currentLabel);
    auto* logText = new QPlainTextEdit(statusWidget);
    logText->setReadOnly(true);
    logText->setAccessibleName(QStringLiteral("Bisect log"));
    statusLayout->addWidget(logText, 1);
    auto* actionRow = new QHBoxLayout();
    auto* goodButton = new QPushButton(QStringLiteral("Mark Good"), statusWidget);
    auto* badButton = new QPushButton(QStringLiteral("Mark Bad"), statusWidget);
    auto* skipButton = new QPushButton(QStringLiteral("Skip"), statusWidget);
    auto* resetButton = new QPushButton(QStringLiteral("Reset (end bisect)"), statusWidget);
    actionRow->addWidget(goodButton);
    actionRow->addWidget(badButton);
    actionRow->addWidget(skipButton);
    actionRow->addStretch(1);
    actionRow->addWidget(resetButton);
    statusLayout->addLayout(actionRow);
    layout->addWidget(statusWidget);

    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    layout->addWidget(closeButton, 0, Qt::AlignRight);
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);

    auto reload = [session, startForm, statusWidget, currentLabel, logText] {
        auto status = session->bisectStatus();
        const bool active = status && status->active;
        startForm->setVisible(!active);
        statusWidget->setVisible(active);
        if (!active) {
            return;
        }
        QString summary = QStringLiteral("Currently testing: %1")
                              .arg(QString::fromStdString(status->currentOid).left(12));
        if (!status->badOid.empty()) {
            summary +=
                QStringLiteral("\nBad: %1").arg(QString::fromStdString(status->badOid).left(12));
        }
        if (!status->goodOids.empty()) {
            summary += QStringLiteral("\nGood: %1 commit(s) marked").arg(status->goodOids.size());
        }
        if (!status->skippedOids.empty()) {
            summary += QStringLiteral("\nSkipped: %1 commit(s)").arg(status->skippedOids.size());
        }
        currentLabel->setText(summary);
        logText->setPlainText(QString::fromStdString(status->logText));
    };
    connect(session, &RepositorySession::bisectStatusUpdated, this, reload);
    session->refreshBisectStatus();
    reload();

    connect(
        startButton, &QPushButton::clicked, this, [session, runWithFeedback, badEdit, goodEdit] {
            BisectStartRequest request;
            request.badRef = badEdit->text().toStdString();
            if (!goodEdit->text().isEmpty()) {
                request.goodRefs = {goodEdit->text().toStdString()};
            }
            runWithFeedback([session, request] { session->startBisect(request); }, nullptr);
        });
    connect(goodButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        BisectMarkRequest request;
        request.good = true;
        runWithFeedback([session, request] { session->markBisect(request); }, nullptr);
    });
    connect(badButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        BisectMarkRequest request;
        request.good = false;
        runWithFeedback([session, request] { session->markBisect(request); }, nullptr);
    });
    connect(skipButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        runWithFeedback([session] { session->skipBisect(BisectSkipRequest{}); }, nullptr);
    });
    connect(resetButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        runWithFeedback([session] { session->resetBisect(BisectResetRequest{}); }, nullptr);
    });

    resize(560, 420);
}

}  // namespace gbm
