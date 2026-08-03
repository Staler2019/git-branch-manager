#include "app/views/pages/DiffPage.h"

#include "app/bridge/ThemeManager.h"
#include "app/views/SideBySideDiffView.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QMouseEvent>
#include <QScrollArea>
#include <QVBoxLayout>

#include <functional>
#include <utility>

namespace gbm {

namespace {

/// A header row that reports clicks via a plain callback rather than a Qt
/// signal -- the same convention WorkingCopyView's FileListWidget uses for
/// its onFileDropped callback, which avoids needing a Q_OBJECT class (and the
/// accompanying `#include "DiffPage.moc"`) defined inside a .cpp file.
class ClickableHeader : public QWidget {
public:
    explicit ClickableHeader(QWidget* parent) : QWidget(parent) {
        setCursor(Qt::PointingHandCursor);
    }

    std::function<void()> onClicked;

protected:
    void mousePressEvent(QMouseEvent* event) override {
        if (event->button() == Qt::LeftButton && onClicked) {
            onClicked();
        }
        QWidget::mousePressEvent(event);
    }
};

}  // namespace

DiffPage::DiffPage(QWidget* parent) : QWidget(parent) {
    auto* layout = new QVBoxLayout(this);

    headerLabel_ = new QLabel(QStringLiteral("No comparison yet — right-click a commit and choose "
                                             "\"Compare with working copy\""),
                              this);
    headerLabel_->setWordWrap(true);
    layout->addWidget(headerLabel_);

    emptyLabel_ = new QLabel(this);
    emptyLabel_->setAlignment(Qt::AlignCenter);
    emptyLabel_->setStyleSheet(
        QStringLiteral("color: %1;").arg(ThemeManager::color(Token::TextTertiary).name()));
    emptyLabel_->setVisible(false);
    layout->addWidget(emptyLabel_, 1);

    scrollArea_ = new QScrollArea(this);
    scrollArea_->setWidgetResizable(true);
    scrollArea_->setFrameShape(QFrame::NoFrame);

    sectionsContainer_ = new QWidget(scrollArea_);
    sectionsLayout_ = new QVBoxLayout(sectionsContainer_);
    // The reported gap: the old flat layout set neither spacing nor margins,
    // so files ran together with only Qt's defaults between them.
    sectionsLayout_->setContentsMargins(12, 12, 12, 12);
    sectionsLayout_->setSpacing(8);
    sectionsLayout_->addStretch(1);
    scrollArea_->setWidget(sectionsContainer_);
    layout->addWidget(scrollArea_, 1);
}

void DiffPage::showCompareWithWorkingCopy(const ObjectId& commit,
                                          std::shared_ptr<const ParsedDiff> diff) {
    headerLabel_->setText(QStringLiteral("Comparing %1 with the working copy")
                              .arg(QString::fromStdString(commit.shortHex(7))));
    // Not staged: an arbitrary historical commit against the work tree isn't
    // the index, so there is nothing for "Stage Line"/"Stage Hunk" to mean.
    stageable_ = false;
    showingStaged_ = false;
    rebuildSections(std::move(diff));
}

void DiffPage::showWorkingCopyDiff(const QString& path,
                                   bool staged,
                                   std::shared_ptr<const ParsedDiff> diff) {
    headerLabel_->setText(staged ? QStringLiteral("Staged changes — %1").arg(path)
                                 : QStringLiteral("Unstaged changes — %1").arg(path));
    // A real index/work-tree (or HEAD/index) diff: stageable both ways.
    stageable_ = true;
    showingStaged_ = staged;
    rebuildSections(std::move(diff));
}

void DiffPage::showMessage(const QString& message) {
    headerLabel_->setText(message);
    clearSections();
    emptyLabel_->setText(message);
    emptyLabel_->setVisible(true);
    scrollArea_->setVisible(false);
}

void DiffPage::clearDiff() {
    headerLabel_->setText(
        QStringLiteral("No comparison yet — right-click a commit and choose "
                       "\"Compare with working copy\""));
    clearSections();
    collapsedPaths_.clear();
    emptyLabel_->setVisible(false);
    scrollArea_->setVisible(true);
}

void DiffPage::refreshTheme() {
    for (const auto& section : sections_) {
        if (section->diffView != nullptr) {
            section->diffView->refreshTheme();
        }
    }
}

void DiffPage::clearSections() {
    for (const auto& section : sections_) {
        // removeWidget first: deleteLater() alone only unparents the widget
        // once the event loop next runs, so rebuildSections's very next
        // `sectionsLayout_->count()` (used to find the trailing stretch
        // item) would still count these as present and insert new sections
        // in the wrong place.
        sectionsLayout_->removeWidget(section->frame);
        section->frame->deleteLater();
    }
    sections_.clear();
}

void DiffPage::rebuildSections(std::shared_ptr<const ParsedDiff> diff) {
    clearSections();
    diff_ = std::move(diff);

    if (!diff_ || diff_->files.empty()) {
        emptyLabel_->setText(QStringLiteral("No changes to show"));
        emptyLabel_->setVisible(true);
        scrollArea_->setVisible(false);
        return;
    }
    emptyLabel_->setVisible(false);
    scrollArea_->setVisible(true);

    // addStretch(1) above keeps sections pinned to the top when there are few
    // of them; new sections are inserted before it.
    const int insertionIndex = sectionsLayout_->count() - 1;

    for (std::size_t i = 0; i < diff_->files.size(); ++i) {
        const DiffFile& file = diff_->files[i];
        auto section = std::make_unique<FileSection>();
        section->path = QString::fromStdString(file.displayPath());

        auto* frame = new QWidget(sectionsContainer_);
        frame->setObjectName(QStringLiteral("gbmPanel"));
        auto* frameLayout = new QVBoxLayout(frame);
        frameLayout->setContentsMargins(0, 0, 0, 0);
        frameLayout->setSpacing(0);

        auto* header = new ClickableHeader(frame);
        header->setObjectName(QStringLiteral("gbmPanelHeader"));
        auto* headerLayout = new QHBoxLayout(header);
        headerLayout->setContentsMargins(10, 6, 10, 6);

        auto* arrowLabel = new QLabel(header);
        arrowLabel->setFixedWidth(14);
        headerLayout->addWidget(arrowLabel);

        QString title = section->path;
        switch (file.kind) {
            case FileChangeKind::Added:
                title += QStringLiteral("  (new file)");
                break;
            case FileChangeKind::Deleted:
                title += QStringLiteral("  (deleted)");
                break;
            case FileChangeKind::Renamed:
                title =
                    QString::fromStdString(file.oldPath) + QStringLiteral("  →  ") + section->path;
                break;
            case FileChangeKind::Copied:
                title += QStringLiteral("  (copied from ") + QString::fromStdString(file.oldPath) +
                         QStringLiteral(")");
                break;
            default:
                break;
        }
        auto* pathLabel = new QLabel(title, header);
        headerLayout->addWidget(pathLabel, 1);

        if (file.addedLines > 0 || file.removedLines > 0) {
            auto* statsLabel = new QLabel(header);
            statsLabel->setText(QStringLiteral("<span style=\"color:%1\">+%2</span> "
                                               "<span style=\"color:%3\">-%4</span>")
                                    .arg(ThemeManager::color(Token::DiffAddText).name())
                                    .arg(file.addedLines)
                                    .arg(ThemeManager::color(Token::DiffDelText).name())
                                    .arg(file.removedLines));
            headerLayout->addWidget(statsLabel);
        }

        frameLayout->addWidget(header);

        section->frame = frame;
        section->header = header;
        section->arrowLabel = arrowLabel;

        const bool defaultExpanded = (i == 0);
        const bool expanded = collapsedPaths_.contains(section->path) ? false : defaultExpanded;

        FileSection* rawSection = section.get();
        header->onClicked = [this, rawSection] {
            setSectionExpanded(*rawSection, !rawSection->expanded);
        };

        sectionsLayout_->insertWidget(insertionIndex + static_cast<int>(i), frame);
        sections_.push_back(std::move(section));

        setSectionExpanded(*rawSection, expanded);
    }
}

void DiffPage::ensureSectionBodyBuilt(FileSection& section) {
    if (section.body != nullptr) {
        return;
    }

    auto* body = new QWidget(section.frame);
    auto* bodyLayout = new QVBoxLayout(body);
    bodyLayout->setContentsMargins(1, 0, 1, 1);

    auto* diffView = new SideBySideDiffView(body);
    diffView->setStagingEnabled(stageable_);
    diffView->setShowingStagedDiff(showingStaged_);
    if (diff_) {
        diffView->showFile(diff_, section.path);
    }
    // sizeHint() alone is enough when this body is the layout's only voice on
    // its own height, but a QVBoxLayout item competing with siblings for
    // space can still get squeezed below it. A minimum height pins the floor
    // explicitly so an expanded section always shows its content rather than
    // falling back to the pane's own inner scrollbar -- set after showFile()
    // so it reflects this diff's actual row count, not an empty view's.
    diffView->setMinimumHeight(diffView->preferredHeight());
    connect(
        diffView, &SideBySideDiffView::applyPatchRequested, this, &DiffPage::applyPatchRequested);
    bodyLayout->addWidget(diffView);

    static_cast<QVBoxLayout*>(section.frame->layout())->addWidget(body);

    section.body = body;
    section.diffView = diffView;
}

void DiffPage::setSectionExpanded(FileSection& section, bool expanded) {
    section.expanded = expanded;
    section.arrowLabel->setText(expanded ? QStringLiteral("▾") : QStringLiteral("▸"));

    if (expanded) {
        collapsedPaths_.remove(section.path);
        ensureSectionBodyBuilt(section);
        section.body->setVisible(true);
    } else {
        collapsedPaths_.insert(section.path);
        if (section.body != nullptr) {
            section.body->setVisible(false);
        }
    }
}

}  // namespace gbm
