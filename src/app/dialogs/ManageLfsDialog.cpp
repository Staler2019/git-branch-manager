#include "app/dialogs/ManageLfsDialog.h"

#include "app/bridge/RepositorySession.h"
#include "app/dialogs/MessageDialogs.h"

#include <QAbstractItemView>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QInputDialog>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

namespace gbm {

ManageLfsDialog::ManageLfsDialog(RepositorySession* session,
                                 RunWithFeedbackFn runWithFeedback,
                                 QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Manage LFS"));
    auto* layout = new QVBoxLayout(this);

    auto* statusLabel = new QLabel(this);
    statusLabel->setWordWrap(true);
    layout->addWidget(statusLabel);

    auto* installButton = new QPushButton(QStringLiteral("Set up LFS for this repository"), this);
    layout->addWidget(installButton);

    auto* patternsGroup = new QWidget(this);
    auto* patternsLayout = new QVBoxLayout(patternsGroup);
    patternsLayout->setContentsMargins(0, 0, 0, 0);
    patternsLayout->addWidget(new QLabel(QStringLiteral("Tracked patterns:"), patternsGroup));
    auto* patternsList = new QListWidget(patternsGroup);
    patternsList->setAccessibleName(QStringLiteral("LFS tracked patterns"));
    patternsList->setMaximumHeight(100);
    patternsLayout->addWidget(patternsList);
    auto* patternButtons = new QHBoxLayout();
    auto* addPatternButton = new QPushButton(QStringLiteral("Track pattern…"), patternsGroup);
    auto* removePatternButton = new QPushButton(QStringLiteral("Untrack"), patternsGroup);
    patternButtons->addWidget(addPatternButton);
    patternButtons->addWidget(removePatternButton);
    patternButtons->addStretch(1);
    patternsLayout->addLayout(patternButtons);
    layout->addWidget(patternsGroup);

    auto* filesTable = new QTableWidget(this);
    filesTable->setColumnCount(3);
    filesTable->setHorizontalHeaderLabels(
        {QStringLiteral("Path"), QStringLiteral("Object"), QStringLiteral("Local")});
    filesTable->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Stretch);
    filesTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
    filesTable->verticalHeader()->setVisible(false);
    filesTable->setAccessibleName(QStringLiteral("LFS files"));
    layout->addWidget(filesTable, 1);

    auto* transferRow = new QHBoxLayout();
    auto* pullButton = new QPushButton(QStringLiteral("Pull"), this);
    auto* fetchButton = new QPushButton(QStringLiteral("Fetch"), this);
    auto* pruneButton = new QPushButton(QStringLiteral("Prune"), this);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    transferRow->addWidget(pullButton);
    transferRow->addWidget(fetchButton);
    transferRow->addWidget(pruneButton);
    transferRow->addStretch(1);
    transferRow->addWidget(closeButton);
    layout->addLayout(transferRow);
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);

    auto reload = [session,
                   statusLabel,
                   installButton,
                   patternsGroup,
                   filesTable,
                   pullButton,
                   fetchButton,
                   pruneButton,
                   patternsList] {
        auto installation = session->lfsInstallation();
        const bool available = installation && installation->available;
        installButton->setVisible(available);
        patternsGroup->setVisible(available);
        filesTable->setVisible(available);
        pullButton->setEnabled(available);
        fetchButton->setEnabled(available);
        pruneButton->setEnabled(available);

        if (!installation) {
            statusLabel->setText(QStringLiteral("Checking for Git LFS…"));
            return;
        }
        if (!available) {
            statusLabel->setText(
                QStringLiteral("Git LFS is not installed. Install the git-lfs extension to "
                               "track large files in this repository."));
            return;
        }
        statusLabel->setText(
            QStringLiteral("Git LFS is available (%1).")
                .arg(QString::fromStdString(installation->version).split(QChar(' ')).value(0)));

        patternsList->clear();
        if (auto patterns = session->lfsTrackedPatterns()) {
            for (const std::string& pattern : *patterns) {
                patternsList->addItem(QString::fromStdString(pattern));
            }
        }

        filesTable->setRowCount(0);
        if (auto files = session->lfsFiles()) {
            filesTable->setRowCount(static_cast<int>(files->size()));
            for (int row = 0; row < static_cast<int>(files->size()); ++row) {
                const LfsFileInfo& info = (*files)[static_cast<std::size_t>(row)];
                filesTable->setItem(
                    row, 0, new QTableWidgetItem(QString::fromStdString(info.path)));
                filesTable->setItem(
                    row, 1, new QTableWidgetItem(QString::fromStdString(info.oid).left(10)));
                filesTable->setItem(
                    row,
                    2,
                    new QTableWidgetItem(info.downloadedLocally ? QStringLiteral("yes")
                                                                : QStringLiteral("no")));
            }
        }
    };
    connect(session, &RepositorySession::lfsUpdated, this, reload);
    session->refreshLfs();
    reload();

    connect(installButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        runWithFeedback([session] { session->installLfs(); }, nullptr);
    });

    connect(addPatternButton, &QPushButton::clicked, this, [this, session, runWithFeedback] {
        const auto patternResult = dialogs::promptText(
            this, QStringLiteral("Track pattern"), QStringLiteral("Pattern (e.g. *.psd):"));
        if (!patternResult || patternResult->isEmpty()) {
            return;
        }
        const QString pattern = *patternResult;
        LfsTrackRequest request;
        request.pattern = pattern.toStdString();
        runWithFeedback([session, request] { session->trackLfsPattern(request); }, nullptr);
    });

    connect(
        removePatternButton, &QPushButton::clicked, this, [session, runWithFeedback, patternsList] {
            const auto items = patternsList->selectedItems();
            if (items.isEmpty()) {
                return;
            }
            LfsUntrackRequest request;
            request.pattern = items.first()->text().toStdString();
            runWithFeedback([session, request] { session->untrackLfsPattern(request); }, nullptr);
        });

    connect(pullButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        runWithFeedback([session] { session->pullLfs(LfsTransferRequest{}); }, nullptr);
    });
    connect(fetchButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        runWithFeedback([session] { session->fetchLfs(LfsTransferRequest{}); }, nullptr);
    });
    connect(pruneButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        runWithFeedback([session] { session->pruneLfs(LfsPruneRequest{}); }, nullptr);
    });

    resize(640, 480);
}

}  // namespace gbm
