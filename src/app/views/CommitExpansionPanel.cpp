#include "app/views/CommitExpansionPanel.h"

#include "app/bridge/ThemeManager.h"
#include "app/models/CommitRowDelegate.h"
#include "app/theme/Metrics.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QScrollArea>
#include <QVBoxLayout>

#include <algorithm>

namespace gbm {

CommitExpansionPanel::CommitExpansionPanel(QPersistentModelIndex commitIndex, QWidget* parent)
    : QWidget(parent), commitIndex_(std::move(commitIndex)) {
    auto* outer = new QVBoxLayout(this);
    outer->setContentsMargins(0, 0, 0, kSpace2);
    outer->setSpacing(0);
    // Reserved, unpainted-by-layout space for the top strip: paintEvent()
    // draws directly into this band via CommitRowDelegate::paintRow, so the
    // strip is pixel-identical to a collapsed row instead of a second,
    // independently maintained summary layout.
    outer->addSpacing(ThemeManager::rowHeight());

    card_ = new QWidget(this);
    card_->setObjectName(QStringLiteral("gbmExpansionCard"));
    cardLayout_ = new QVBoxLayout(card_);
    cardLayout_->setContentsMargins(kSpace3, kSpace2, kSpace3, kSpace2);
    cardLayout_->setSpacing(kSpace1);

    summaryLabel_ = new QLabel(card_);
    summaryLabel_->setObjectName(QStringLiteral("gbmExpansionSummary"));
    cardLayout_->addWidget(summaryLabel_);

    fileListWidget_ = new QWidget(card_);
    fileListLayout_ = new QVBoxLayout(fileListWidget_);
    fileListLayout_->setContentsMargins(0, 0, 0, 0);
    fileListLayout_->setSpacing(2);

    fileScroll_ = new QScrollArea(card_);
    fileScroll_->setWidget(fileListWidget_);
    fileScroll_->setWidgetResizable(true);
    fileScroll_->setFrameShape(QFrame::NoFrame);
    fileScroll_->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    fileScroll_->setVisible(false);
    cardLayout_->addWidget(fileScroll_);

    outer->addWidget(card_, 0, Qt::AlignTop);

    rebuildFileList();
}

void CommitExpansionPanel::setDetails(std::shared_ptr<const std::vector<ChangedFile>> files,
                                      std::shared_ptr<const ParsedDiff> diff) {
    files_ = std::move(files);
    diff_ = std::move(diff);
    hasDetails_ = true;
    rebuildFileList();
    updateGeometry();
}

void CommitExpansionPanel::rebuildFileList() {
    QLayoutItem* item = nullptr;
    while ((item = fileListLayout_->takeAt(0)) != nullptr) {
        delete item->widget();
        delete item;
    }

    if (!hasDetails_) {
        summaryLabel_->setText(QStringLiteral("Loading changes…"));
        fileScroll_->setVisible(false);
        return;
    }

    const int fileCount = files_ ? static_cast<int>(files_->size()) : 0;
    summaryLabel_->setText(
        QStringLiteral("%1 file%2 changed — right-click the commit row for actions")
            .arg(fileCount)
            .arg(fileCount == 1 ? QString() : QStringLiteral("s")));

    for (int i = 0; i < fileCount; ++i) {
        const ChangedFile& file = (*files_)[static_cast<std::size_t>(i)];
        const QString path = QString::fromStdString(file.path);

        // Line-count badges come from the parallel ParsedDiff, keyed by path
        // -- ChangedFile itself carries no added/removed counts.
        std::uint32_t added = 0;
        std::uint32_t removed = 0;
        if (diff_) {
            for (const DiffFile& diffFile : diff_->files) {
                if (diffFile.displayPath() == file.path) {
                    added = diffFile.addedLines;
                    removed = diffFile.removedLines;
                    break;
                }
            }
        }

        auto* row = new QWidget(fileListWidget_);
        row->setFixedHeight(kFileRowHeight);
        auto* rowLayout = new QHBoxLayout(row);
        rowLayout->setContentsMargins(0, 0, 0, 0);
        rowLayout->setSpacing(kSpace2);

        auto* pathLabel = new QLabel(path.toHtmlEscaped(), row);
        pathLabel->setFont(ThemeManager::monoFont(kTextXs));
        pathLabel->setStyleSheet(
            QStringLiteral("color: %1;").arg(ThemeManager::color(Token::TextPrimary).name()));
        rowLayout->addWidget(pathLabel, 1);

        auto* addedBadge = new QLabel(QStringLiteral("+%1").arg(added), row);
        addedBadge->setObjectName(QStringLiteral("gbmBadgeAdded"));
        addedBadge->setAlignment(Qt::AlignCenter);
        addedBadge->setFont(ThemeManager::monoFont(kTextXs));
        rowLayout->addWidget(addedBadge);

        auto* removedBadge = new QLabel(QStringLiteral("-%1").arg(removed), row);
        removedBadge->setObjectName(QStringLiteral("gbmBadgeRemoved"));
        removedBadge->setAlignment(Qt::AlignCenter);
        removedBadge->setFont(ThemeManager::monoFont(kTextXs));
        rowLayout->addWidget(removedBadge);

        fileListLayout_->addWidget(row);
    }
    fileListLayout_->addStretch(1);

    const int shownRows = std::min(fileCount, kMaxVisibleFileRows);
    fileScroll_->setVisible(fileCount > 0);
    fileScroll_->setFixedHeight(shownRows * kFileRowHeight);
}

void CommitExpansionPanel::paintEvent(QPaintEvent* event) {
    QWidget::paintEvent(event);
    QPainter painter(this);
    const QRect stripRect(0, 0, width(), ThemeManager::rowHeight());
    // Always selected: expansion only ever toggles on a row that is already
    // selected (see MainWindow.h's invariant comment on expandedCommitRow_),
    // so the strip always shows the selected-row background.
    CommitRowDelegate::paintRow(&painter, stripRect, commitIndex_, /*selected=*/true);
}

}  // namespace gbm
