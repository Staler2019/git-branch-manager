#include "app/dialogs/GraphBranchFilterDialog.h"

#include <QDialogButtonBox>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QVBoxLayout>

#include <set>

namespace gbm {

namespace {
constexpr int kFullNameRole = Qt::UserRole + 1;
}  // namespace

GraphBranchFilterDialog::GraphBranchFilterDialog(const RefSnapshot& refs,
                                                 const std::vector<std::string>& selected,
                                                 QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Branches shown on graph"));
    auto* layout = new QVBoxLayout(this);

    auto* captionLabel = new QLabel(
        QStringLiteral("Leave everything unchecked to show the full history. Check specific "
                       "branches to limit the graph to just their commits."),
        this);
    captionLabel->setWordWrap(true);
    layout->addWidget(captionLabel);

    const std::set<std::string> selectedSet(selected.begin(), selected.end());

    list_ = new QListWidget(this);
    for (const RefInfo& ref : refs.refs) {
        if (ref.kind != RefKind::LocalBranch && ref.kind != RefKind::RemoteBranch) {
            continue;
        }
        auto* item = new QListWidgetItem(QString::fromStdString(ref.shortName), list_);
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(selectedSet.count(ref.fullName) > 0 ? Qt::Checked : Qt::Unchecked);
        item->setData(kFullNameRole, QString::fromStdString(ref.fullName));
    }
    layout->addWidget(list_, 1);

    auto* clearButton = new QPushButton(QStringLiteral("Uncheck all (show everything)"), this);
    connect(clearButton, &QPushButton::clicked, this, [this] {
        for (int row = 0; row < list_->count(); ++row) {
            list_->item(row)->setCheckState(Qt::Unchecked);
        }
    });
    layout->addWidget(clearButton);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);

    resize(360, 420);
}

std::vector<std::string> GraphBranchFilterDialog::selectedRefs() const {
    std::vector<std::string> result;
    for (int row = 0; row < list_->count(); ++row) {
        const QListWidgetItem* item = list_->item(row);
        if (item->checkState() == Qt::Checked) {
            result.push_back(item->data(kFullNameRole).toString().toStdString());
        }
    }
    return result;
}

}  // namespace gbm
