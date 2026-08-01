#include "app/views/pages/DiffPage.h"

#include "app/views/DiffView.h"

#include <QLabel>
#include <QVBoxLayout>

namespace gbm {

DiffPage::DiffPage(QWidget* parent) : QWidget(parent) {
    auto* layout = new QVBoxLayout(this);

    headerLabel_ = new QLabel(QStringLiteral("No comparison yet — right-click a commit and choose "
                                             "\"Compare with working copy\""),
                              this);
    headerLabel_->setWordWrap(true);
    layout->addWidget(headerLabel_);

    diffView_ = new DiffView(this);
    // Read-only: this pane shows a past commit against the work tree, which
    // cannot be staged the way WorkingCopyView's embedded DiffView can.
    diffView_->setStagingEnabled(false);
    layout->addWidget(diffView_, 1);
}

void DiffPage::showCompareWithWorkingCopy(const ObjectId& commit,
                                          std::shared_ptr<const ParsedDiff> diff) {
    headerLabel_->setText(QStringLiteral("Comparing %1 with the working copy")
                              .arg(QString::fromStdString(commit.shortHex(7))));
    diffView_->showDiff(std::move(diff));
}

void DiffPage::showWorkingCopyDiff(const QString& path,
                                   bool staged,
                                   std::shared_ptr<const ParsedDiff> diff) {
    headerLabel_->setText(staged ? QStringLiteral("Staged changes — %1").arg(path)
                                 : QStringLiteral("Unstaged changes — %1").arg(path));
    diffView_->showDiff(std::move(diff));
}

void DiffPage::showMessage(const QString& message) {
    headerLabel_->setText(message);
    diffView_->showMessage(message);
}

void DiffPage::clearDiff() {
    headerLabel_->setText(
        QStringLiteral("No comparison yet — right-click a commit and choose "
                       "\"Compare with working copy\""));
    diffView_->clearDiff();
}

void DiffPage::refreshTheme() {
    diffView_->refreshTheme();
}

}  // namespace gbm
