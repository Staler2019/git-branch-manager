#include "app/dialogs/CleanUntrackedDialog.h"

#include "app/bridge/RepositorySession.h"

#include <QCheckBox>
#include <QHBoxLayout>
#include <QListWidget>
#include <QMessageBox>
#include <QPushButton>
#include <QVBoxLayout>

namespace gbm {

CleanUntrackedDialog::CleanUntrackedDialog(RepositorySession* session,
                                           RunWithFeedbackFn runWithFeedback,
                                           QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Clean untracked files"));
    auto* layout = new QVBoxLayout(this);

    auto* includeIgnored = new QCheckBox(QStringLiteral("Also remove ignored files"), this);
    layout->addWidget(includeIgnored);

    auto* list = new QListWidget(this);
    layout->addWidget(list, 1);

    connect(session,
            &RepositorySession::cleanPreviewReady,
            this,
            [list](std::vector<CleanEntry> entries) {
                list->clear();
                for (const CleanEntry& entry : entries) {
                    auto* item = new QListWidgetItem(
                        QString::fromStdString(entry.path) +
                            (entry.isDirectory ? QStringLiteral("/") : QString()),
                        list);
                    item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
                    item->setCheckState(Qt::Checked);
                    item->setData(Qt::UserRole, QString::fromStdString(entry.path));
                }
            });
    auto reload = [session, includeIgnored] {
        session->requestCleanPreview(includeIgnored->isChecked());
    };
    connect(includeIgnored, &QCheckBox::toggled, this, [reload](bool) { reload(); });
    reload();

    auto* buttonRow = new QHBoxLayout();
    auto* removeButton = new QPushButton(QStringLiteral("Remove"), this);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    buttonRow->addStretch(1);
    buttonRow->addWidget(removeButton);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(removeButton,
            &QPushButton::clicked,
            this,
            [this, session, runWithFeedback, list, includeIgnored] {
                std::vector<std::string> paths;
                for (int i = 0; i < list->count(); ++i) {
                    auto* item = list->item(i);
                    if (item->checkState() == Qt::Checked) {
                        paths.push_back(item->data(Qt::UserRole).toString().toStdString());
                    }
                }
                if (paths.empty()) {
                    return;
                }
                const auto confirmed =
                    QMessageBox::warning(this,
                                         QStringLiteral("Remove untracked files?"),
                                         QStringLiteral("This permanently deletes %1 item(s). "
                                                        "This cannot be undone.")
                                             .arg(paths.size()),
                                         QMessageBox::Discard | QMessageBox::Cancel,
                                         QMessageBox::Cancel);
                if (confirmed != QMessageBox::Discard) {
                    return;
                }
                CleanRequest request;
                request.paths = paths;
                request.includeIgnored = includeIgnored->isChecked();
                runWithFeedback([session, request] { session->cleanUntracked(request); }, nullptr);
                accept();
            });
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);

    resize(480, 400);
}

}  // namespace gbm
