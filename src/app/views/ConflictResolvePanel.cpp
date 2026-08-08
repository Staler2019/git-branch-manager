#include "app/views/ConflictResolvePanel.h"

#include "app/bridge/RepositorySession.h"
#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/ConflictOps.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QVBoxLayout>

namespace gbm {

ConflictResolvePanel::ConflictResolvePanel(QWidget* parent) : QWidget(parent) {
    auto* layout = new QVBoxLayout(this);

    kindLabel_ = new QLabel(this);
    kindLabel_->setVisible(false);
    layout->addWidget(kindLabel_);

    auto* panesLayout = new QHBoxLayout();
    auto makePane = [&](const QString& title) {
        auto* container = new QWidget(this);
        auto* paneLayout = new QVBoxLayout(container);
        paneLayout->setContentsMargins(0, 0, 0, 0);
        paneLayout->addWidget(new QLabel(title, container));
        auto* edit = new QPlainTextEdit(container);
        edit->setReadOnly(true);
        edit->setLineWrapMode(QPlainTextEdit::NoWrap);
        edit->setPlainText(tr("Loading…"));
        paneLayout->addWidget(edit, 1);
        panesLayout->addWidget(container);
        return edit;
    };
    ancestorEdit_ = makePane(tr("Common ancestor"));
    oursEdit_ = makePane(tr("Mine (ours)"));
    theirsEdit_ = makePane(tr("Theirs"));
    layout->addLayout(panesLayout, 1);

    auto* buttonRow = new QHBoxLayout();
    auto* takeOursButton = new QPushButton(tr("Take Mine"), this);
    auto* takeTheirsButton = new QPushButton(tr("Take Theirs"), this);
    auto* markResolvedButton = new QPushButton(tr("Mark Resolved"), this);
    auto* cancelButton = new QPushButton(tr("Cancel"), this);
    buttonRow->addWidget(takeOursButton);
    buttonRow->addWidget(takeTheirsButton);
    buttonRow->addWidget(markResolvedButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(cancelButton);
    layout->addLayout(buttonRow);

    connect(takeOursButton, &QPushButton::clicked, this, [this] { submitResolution(1); });
    connect(takeTheirsButton, &QPushButton::clicked, this, [this] { submitResolution(2); });
    connect(markResolvedButton, &QPushButton::clicked, this, [this] { submitResolution(3); });
    connect(cancelButton, &QPushButton::clicked, this, [this] { submitResolution(0); });
}

void ConflictResolvePanel::showEntry(RepositorySession* session, const WorkingCopyEntry& entry) {
    session_ = session;
    path_ = entry.path;
    oursBlobMissing_ = entry.oursBlob.empty();
    theirsBlobMissing_ = entry.theirsBlob.empty();

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

    // Scoped to this widget's lifetime: if the request's reply arrives after
    // the panel has already been destroyed, Qt drops the connection rather
    // than calling back into a dangling this.
    connect(session_,
            &RepositorySession::conflictSidesReady,
            this,
            &ConflictResolvePanel::onConflictSidesReady);
    session_->requestConflictSides(entry.path, entry.ancestorBlob, entry.oursBlob, entry.theirsBlob);
}

void ConflictResolvePanel::onConflictSidesReady(const QString& path,
                                                 const QString& ancestor,
                                                 const QString& ours,
                                                 const QString& theirs) {
    if (path.toStdString() != path_) {
        return;
    }
    ancestorEdit_->setPlainText(ancestor);
    oursEdit_->setPlainText(ours);
    theirsEdit_->setPlainText(theirs);
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
        default:
            request.resolution = ConflictResolution::MarkResolved;
            break;
    }
    session_->resolveConflict(request);
    emit resolutionSubmitted();
}

}  // namespace gbm
