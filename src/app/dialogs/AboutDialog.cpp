#include "app/dialogs/AboutDialog.h"

#include "gbm/Version.h"

#include <QFont>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>

namespace gbm {

AboutDialog::AboutDialog(QWidget* parent) : QDialog(parent) {
    setWindowTitle(QStringLiteral("About git-branch-manager"));
    auto* layout = new QVBoxLayout(this);

    auto* title = new QLabel(QStringLiteral("git-branch-manager"), this);
    QFont titleFont = title->font();
    titleFont.setBold(true);
    titleFont.setPointSize(titleFont.pointSize() + 4);
    title->setFont(titleFont);
    layout->addWidget(title);

    layout->addWidget(
        new QLabel(QStringLiteral("Version %1").arg(QStringLiteral(GBM_VERSION_STRING)), this));
    layout->addWidget(
        new QLabel(QStringLiteral("A Git client for very large repositories."), this));

    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);
    layout->addWidget(closeButton, 0, Qt::AlignRight);

    resize(360, 160);
}

}  // namespace gbm
