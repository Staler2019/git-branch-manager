#include "app/views/ConflictResolvePanel.h"

#include "app/bridge/RepositorySession.h"
#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/ConflictOps.h"

#include <QCheckBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSettings>
#include <QSplitter>
#include <QTimer>
#include <QVBoxLayout>

#include <utility>

namespace gbm {

namespace {

/// Mirrors WorkingCopyView::setupPersistentSplitter exactly -- both read the
/// same `window/splitters/<key>` QSettings keys. Duplicated rather than
/// shared: the two classes have no common base to hang a helper off, same
/// reasoning as WorkingCopyView's own copy.
void setupPersistentSplitter(QSplitter* splitter, const QString& key) {
    const QString settingsKey = QStringLiteral("window/splitters/%1").arg(key);

    QSettings settings;
    const QVariant saved = settings.value(settingsKey);
    if (saved.isValid()) {
        const QVariantList list = saved.toList();
        QList<int> sizes;
        sizes.reserve(list.size());
        for (const QVariant& value : list) {
            sizes.append(value.toInt());
        }
        if (!sizes.isEmpty()) {
            QTimer::singleShot(0, splitter, [splitter, sizes] { splitter->setSizes(sizes); });
        }
    }

    QObject::connect(splitter, &QSplitter::splitterMoved, splitter, [splitter, settingsKey] {
        QSettings settingsToSave;
        QVariantList list;
        for (int size : splitter->sizes()) {
            list.append(size);
        }
        settingsToSave.setValue(settingsKey, list);
    });
}

}  // namespace

ConflictResolvePanel::ConflictResolvePanel(QWidget* parent) : QWidget(parent) {
    auto* layout = new QVBoxLayout(this);

    auto* headerRow = new QHBoxLayout();
    kindLabel_ = new QLabel(this);
    kindLabel_->setVisible(false);
    headerRow->addWidget(kindLabel_, 1);
    ancestorToggle_ = new QCheckBox(tr("Show common ancestor"), this);
    headerRow->addWidget(ancestorToggle_);
    layout->addLayout(headerRow);

    panesSplitter_ = new QSplitter(Qt::Horizontal, this);
    auto makePane = [&](const QString& title) {
        auto* container = new QWidget(panesSplitter_);
        auto* paneLayout = new QVBoxLayout(container);
        paneLayout->setContentsMargins(0, 0, 0, 0);
        paneLayout->addWidget(new QLabel(title, container));
        auto* edit = new QPlainTextEdit(container);
        edit->setReadOnly(true);
        edit->setLineWrapMode(QPlainTextEdit::NoWrap);
        edit->setPlainText(tr("Loading…"));
        paneLayout->addWidget(edit, 1);
        panesSplitter_->addWidget(container);
        return std::pair{container, edit};
    };
    std::tie(ancestorContainer_, ancestorEdit_) = makePane(tr("Common ancestor"));
    ancestorContainer_->setVisible(false);
    std::tie(std::ignore, oursEdit_) = makePane(tr("Current branch (mine)"));
    std::tie(std::ignore, middleEdit_) = makePane(tr("Resolved content (editable)"));
    std::tie(std::ignore, theirsEdit_) = makePane(tr("Merged branch (theirs)"));
    layout->addWidget(panesSplitter_, 1);
    setupPersistentSplitter(panesSplitter_, QStringLiteral("conflictPanes"));

    connect(ancestorToggle_, &QCheckBox::toggled, ancestorContainer_, &QWidget::setVisible);

    auto* buttonRow = new QHBoxLayout();
    auto* takeLeftButton = new QPushButton(tr("Take Left (Mine)"), this);
    auto* takeRightButton = new QPushButton(tr("Take Right (Theirs)"), this);
    saveButton_ = new QPushButton(tr("Save and Mark Resolved"), this);
    saveButton_->setEnabled(false);
    auto* cancelButton = new QPushButton(tr("Cancel"), this);
    buttonRow->addWidget(takeLeftButton);
    buttonRow->addWidget(takeRightButton);
    buttonRow->addWidget(saveButton_);
    buttonRow->addStretch(1);
    buttonRow->addWidget(cancelButton);
    layout->addLayout(buttonRow);

    connect(takeLeftButton, &QPushButton::clicked, this, [this] { submitResolution(1); });
    connect(takeRightButton, &QPushButton::clicked, this, [this] { submitResolution(2); });
    connect(saveButton_, &QPushButton::clicked, this, [this] { submitResolution(3); });
    connect(cancelButton, &QPushButton::clicked, this, [this] { submitResolution(0); });
}

void ConflictResolvePanel::showEntry(RepositorySession* session, const WorkingCopyEntry& entry) {
    session_ = session;
    path_ = entry.path;
    ancestorBlobMissing_ = entry.ancestorBlob.empty();
    oursBlobMissing_ = entry.oursBlob.empty();
    theirsBlobMissing_ = entry.theirsBlob.empty();
    middleContentHasCrlf_ = false;
    middleEditable_ = false;
    saveButton_->setEnabled(false);

    QString kindText;
    switch (entry.conflict) {
        case ConflictKind::BothAdded:
            kindText = tr("Both sides added this file.");
            break;
        case ConflictKind::BothModified:
            kindText = tr("Both sides modified this file.");
            break;
        case ConflictKind::BothDeleted:
            kindText = tr("Both sides deleted this file.");
            break;
        case ConflictKind::AddedByUs:
            kindText = tr("You added this file; the other side did not touch it.");
            break;
        case ConflictKind::DeletedByUs:
            kindText = tr("You deleted this file; the other side modified it.");
            break;
        case ConflictKind::AddedByThem:
            kindText = tr("The other side added this file; you did not touch it.");
            break;
        case ConflictKind::DeletedByThem:
            kindText = tr("The other side deleted this file; you modified it.");
            break;
        case ConflictKind::None:
            break;
    }
    kindLabel_->setText(kindText);
    kindLabel_->setVisible(!kindText.isEmpty());

    ancestorEdit_->setPlainText(tr("Loading…"));
    oursEdit_->setPlainText(tr("Loading…"));
    middleEdit_->setReadOnly(true);
    middleEdit_->setPlainText(tr("Loading…"));
    theirsEdit_->setPlainText(tr("Loading…"));
    if (entry.ancestorBlob.empty()) {
        ancestorEdit_->setPlainText(tr("(no common ancestor)"));
    }
    if (entry.oursBlob.empty()) {
        oursEdit_->setPlainText(tr("(deleted on this side)"));
    }
    if (entry.theirsBlob.empty()) {
        theirsEdit_->setPlainText(tr("(deleted on the other side)"));
    }

    // Scoped to this widget's lifetime: if a reply arrives after the panel
    // has already been destroyed, Qt drops the connection rather than
    // calling back into a dangling this.
    connect(session_,
            &RepositorySession::conflictSidesReady,
            this,
            &ConflictResolvePanel::onConflictSidesReady);
    session_->requestConflictSides(entry.path, entry.ancestorBlob, entry.oursBlob, entry.theirsBlob);

    connect(session_,
            &RepositorySession::workingTreeContentReady,
            this,
            &ConflictResolvePanel::onWorkingTreeContentReady);
    session_->requestWorkingTreeContent(entry.path);
}

void ConflictResolvePanel::onConflictSidesReady(const QString& path,
                                                 const QString& ancestor,
                                                 const QString& ours,
                                                 const QString& theirs) {
    if (path.toStdString() != path_) {
        return;
    }
    if (!ancestorBlobMissing_) {
        ancestorEdit_->setPlainText(ancestor);
    }
    if (!oursBlobMissing_) {
        oursEdit_->setPlainText(ours);
    }
    if (!theirsBlobMissing_) {
        theirsEdit_->setPlainText(theirs);
    }
}

void ConflictResolvePanel::onWorkingTreeContentReady(const QString& path,
                                                      const QString& content,
                                                      bool editable) {
    if (path.toStdString() != path_) {
        return;
    }
    middleEditable_ = editable;
    saveButton_->setEnabled(editable);
    if (editable) {
        middleContentHasCrlf_ = content.contains(QStringLiteral("\r\n"));
        middleEdit_->setReadOnly(false);
        middleEdit_->setPlainText(content);
    } else {
        middleEdit_->setReadOnly(true);
        middleEdit_->setPlainText(
            tr("(binary or non-UTF-8 content — use Take Left or Take Right)"));
    }
}

void ConflictResolvePanel::submitResolution(int choice) {
    if (choice == 0 || session_ == nullptr) {
        emit cancelled();
        return;
    }

    ResolveConflictRequest request;
    request.path = path_;
    request.oursBlobMissing = oursBlobMissing_;
    request.theirsBlobMissing = theirsBlobMissing_;
    switch (choice) {
        case 1:
            request.resolution = ConflictResolution::TakeOurs;
            break;
        case 2:
            request.resolution = ConflictResolution::TakeTheirs;
            break;
        default: {
            if (!middleEditable_) {
                return;
            }
            request.resolution = ConflictResolution::WriteResolved;
            QString edited = middleEdit_->toPlainText();
            if (middleContentHasCrlf_) {
                edited.replace(QStringLiteral("\n"), QStringLiteral("\r\n"));
            }
            request.resolvedContent = edited.toUtf8().toStdString();
            break;
        }
    }
    session_->resolveConflict(request);
    emit resolutionSubmitted();
}

}  // namespace gbm
