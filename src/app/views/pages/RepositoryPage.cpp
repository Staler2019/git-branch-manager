#include "app/views/pages/RepositoryPage.h"

#include <QLabel>
#include <QVBoxLayout>

namespace gbm {

RepositoryPage::RepositoryPage(QWidget* parent) : QWidget(parent) {
    auto* layout = new QVBoxLayout(this);
    auto* label = new QLabel(QStringLiteral("Repository settings — coming in a later phase"), this);
    label->setAlignment(Qt::AlignCenter);
    layout->addWidget(label, 1, Qt::AlignCenter);
}

}  // namespace gbm
