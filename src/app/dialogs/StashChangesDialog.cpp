#include "app/dialogs/StashChangesDialog.h"

#include <QCheckBox>
#include <QDialogButtonBox>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QPushButton>
#include <QVBoxLayout>

#include <set>
#include <utility>

namespace gbm {

namespace {
constexpr int kUntrackedRole = Qt::UserRole + 1;
}  // namespace

StashChangesDialog::StashChangesDialog(WorkingCopyStatusPtr status, QWidget* parent)
    : QDialog(parent), status_(std::move(status)) {
    setWindowTitle(QStringLiteral("Stash changes"));
    auto* layout = new QVBoxLayout(this);

    messageEdit_ = new QLineEdit(this);
    messageEdit_->setPlaceholderText(QStringLiteral("Stash message (optional)"));
    layout->addWidget(messageEdit_);

    layout->addWidget(new QLabel(QStringLiteral("Files to stash:"), this));
    fileList_ = new QListWidget(this);
    layout->addWidget(fileList_, 1);

    includeUntracked_ = new QCheckBox(QStringLiteral("Include untracked files"), this);
    layout->addWidget(includeUntracked_);
    connect(includeUntracked_, &QCheckBox::toggled, this, [this](bool checked) {
        onIncludeUntrackedToggled(checked);
        updateOkEnabled();
    });
    connect(fileList_, &QListWidget::itemChanged, this, [this](QListWidgetItem*) {
        updateOkEnabled();
    });

    buttons_ = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    layout->addWidget(buttons_);
    connect(buttons_, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons_, &QDialogButtonBox::rejected, this, &QDialog::reject);

    rebuildFileList();
    updateOkEnabled();

    resize(420, 360);
}

void StashChangesDialog::rebuildFileList() {
    fileList_->clear();
    if (!status_) {
        return;
    }

    // staged() and unstaged() can share a path (a partially staged file);
    // show it once rather than twice.
    std::set<std::string> seen;
    auto addEntry = [this, &seen](const std::string& path, bool untracked) {
        if (!seen.insert(path).second) {
            return;
        }
        auto* item = new QListWidgetItem(QString::fromStdString(path), fileList_);
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(Qt::Checked);
        item->setData(Qt::UserRole, QString::fromStdString(path));
        item->setData(kUntrackedRole, untracked);
    };

    for (const WorkingCopyEntry* entry : status_->staged()) {
        addEntry(entry->path, false);
    }
    for (const WorkingCopyEntry* entry : status_->unstaged()) {
        addEntry(entry->path, false);
    }
    for (const WorkingCopyEntry* entry : status_->untracked()) {
        addEntry(entry->path, true);
    }

    onIncludeUntrackedToggled(includeUntracked_->isChecked());
}

void StashChangesDialog::onIncludeUntrackedToggled(bool checked) {
    // `git stash push`, even with an explicit pathspec, never stashes
    // untracked files unless --include-untracked is given -- so an untracked
    // row that's checked while the box is off would silently be dropped from
    // the stash. Disabling (and unchecking) it instead makes that visible.
    for (int row = 0; row < fileList_->count(); ++row) {
        QListWidgetItem* item = fileList_->item(row);
        if (!item->data(kUntrackedRole).toBool()) {
            continue;
        }
        item->setFlags(checked ? (item->flags() | Qt::ItemIsEnabled)
                               : (item->flags() & ~Qt::ItemIsEnabled));
        if (!checked) {
            item->setCheckState(Qt::Unchecked);
        } else if (item->checkState() == Qt::Unchecked) {
            item->setCheckState(Qt::Checked);
        }
    }
}

void StashChangesDialog::updateOkEnabled() {
    bool anyChecked = false;
    for (int row = 0; row < fileList_->count() && !anyChecked; ++row) {
        anyChecked = fileList_->item(row)->checkState() == Qt::Checked;
    }
    // Only ever disables: an empty list (no session status passed in, or
    // nothing to stash) should not block a dialog that was reachable in the
    // first place -- StashSaveOperation already refuses that case with its
    // own "no local changes to stash" error.
    buttons_->button(QDialogButtonBox::Ok)->setEnabled(anyChecked || fileList_->count() == 0);
}

StashSaveRequest StashChangesDialog::request() const {
    StashSaveRequest request;
    request.message = messageEdit_->text().toStdString();
    request.includeUntracked = includeUntracked_->isChecked();

    for (int row = 0; row < fileList_->count(); ++row) {
        const QListWidgetItem* item = fileList_->item(row);
        if (item->checkState() == Qt::Checked) {
            request.paths.push_back(item->data(Qt::UserRole).toString().toStdString());
        }
    }
    return request;
}

}  // namespace gbm
