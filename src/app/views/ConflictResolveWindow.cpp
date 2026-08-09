#include "app/views/ConflictResolveWindow.h"

#include "app/bridge/RepositorySession.h"
#include "app/theme/IconLoader.h"
#include "app/theme/Tokens.h"
#include "app/views/ConflictResolvePanel.h"

#include <QCheckBox>
#include <QCloseEvent>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QSettings>
#include <QSplitter>
#include <QTimer>
#include <QVBoxLayout>
#include <QVariantList>

#include <algorithm>

namespace gbm {

std::optional<int> nextUnresolvedRailIndex(const std::vector<ConflictBatchEntry>& entries,
                                            int resolvedIndex) {
    const int count = static_cast<int>(entries.size());
    if (count == 0 || resolvedIndex < 0 || resolvedIndex >= count) {
        return std::nullopt;
    }
    // Same forward-then-wrap-but-never-back-onto-self search as
    // ConflictResolvePanel::resolveRegion() -- see this function's own doc
    // comment in the header for why that's the right shape to mirror here.
    for (int offset = 1; offset < count; ++offset) {
        const int candidate = (resolvedIndex + offset) % count;
        if (entries[static_cast<std::size_t>(candidate)].state == ConflictFileState::Unresolved) {
            return candidate;
        }
    }
    return std::nullopt;
}

namespace {

constexpr int kRailUserRole = Qt::UserRole;

// Untranslated technical shorthand, same convention as ConflictResolvePanel's
// LF/CRLF/Non-UTF-8 badges -- a conflict kind reads the same regardless of
// UI language.
QString conflictKindShortToken(ConflictKind kind) {
    switch (kind) {
        case ConflictKind::BothAdded:
            return QStringLiteral("A/A");
        case ConflictKind::BothModified:
            return QStringLiteral("M/M");
        case ConflictKind::BothDeleted:
            return QStringLiteral("D/D");
        case ConflictKind::AddedByUs:
            return QStringLiteral("A/-");
        case ConflictKind::DeletedByUs:
            return QStringLiteral("D/-");
        case ConflictKind::AddedByThem:
            return QStringLiteral("-/A");
        case ConflictKind::DeletedByThem:
            return QStringLiteral("-/D");
        case ConflictKind::None:
            return QString();
    }
    return QString();
}

QString conflictResolveWindowGeometryKey() {
    return QStringLiteral("window/conflictResolveWindow/geometry");
}

QString conflictWindowSplitterKey() {
    return QStringLiteral("window/splitters/conflictWindowRail");
}

}  // namespace

ConflictResolveWindow::ConflictResolveWindow(QWidget* parent) : QWidget(parent) {
    setWindowFlag(Qt::Window, true);
    setWindowTitle(tr("Resolve Conflicts"));

    railList_ = new QListWidget(this);
    railList_->setObjectName(QStringLiteral("conflictRailList"));
    railList_->setMinimumWidth(200);

    hideResolvedCheckbox_ = new QCheckBox(tr("Hide resolved"), this);
    hideResolvedCheckbox_->setObjectName(QStringLiteral("conflictHideResolvedCheckbox"));
    // Design B2's must_not_do: progress must stay visible by default, so
    // this starts unchecked -- resolved rows stay in the rail unless the
    // user explicitly asks to hide them.
    hideResolvedCheckbox_->setChecked(false);
    connect(hideResolvedCheckbox_, &QCheckBox::toggled, this, [this] { rebuildRailRows(); });

    progressLabel_ = new QLabel(this);
    progressLabel_->setObjectName(QStringLiteral("conflictRailProgressLabel"));

    auto* railContainer = new QWidget(this);
    auto* railLayout = new QVBoxLayout(railContainer);
    railLayout->setContentsMargins(0, 0, 0, 0);
    railLayout->addWidget(hideResolvedCheckbox_);
    railLayout->addWidget(railList_, 1);
    railLayout->addWidget(progressLabel_);
    railContainer->setMinimumWidth(200);

    panel_ = new ConflictResolvePanel(this);
    connect(panel_, &ConflictResolvePanel::resolutionSubmitted, this,
            &ConflictResolveWindow::onPanelResolutionSubmitted);
    // Design B1's three explicit exits (儲存目前進度/全部套用並完成/取消) land in
    // C13 -- cancelled() is deliberately left unconnected here since a
    // single file's cancel no longer means "close the whole window" once
    // several files share one window (there's no equivalent single-file
    // modal to close back to). Revisit once C13 defines what "cancel"
    // means at the window level.
    connect(railList_, &QListWidget::currentItemChanged, this,
            [this](QListWidgetItem* current, QListWidgetItem* /*previous*/) {
                if (current == nullptr) {
                    return;
                }
                selectEntryIndex(current->data(kRailUserRole).toInt());
            });

    splitter_ = new QSplitter(Qt::Horizontal, this);
    splitter_->setObjectName(QStringLiteral("conflictWindowSplitter"));
    splitter_->setHandleWidth(6);
    splitter_->setChildrenCollapsible(false);
    splitter_->addWidget(railContainer);
    splitter_->addWidget(panel_);
    splitter_->setStretchFactor(0, 1);
    splitter_->setStretchFactor(1, 4);
    connect(splitter_, &QSplitter::splitterMoved, this, [this] { saveSplitterSizes(); });

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->addWidget(splitter_);

    QSettings settings;
    const QVariant savedGeometry = settings.value(conflictResolveWindowGeometryKey());
    if (savedGeometry.isValid() && restoreGeometry(savedGeometry.toByteArray())) {
        // Restored successfully.
    } else {
        resize(1400, 900);
        if (parent != nullptr) {
            const QRect parentGeometry = parent->frameGeometry();
            move(parentGeometry.center() - QPoint(width() / 2, height() / 2));
        }
    }
    restoreSplitterSizes();
}

ConflictResolveWindow* ConflictResolveWindow::openFor(QWidget* parent, RepositorySession* session,
                                                       const QString& initialPath) {
    auto* window = new ConflictResolveWindow(parent);
    window->setAttribute(Qt::WA_DeleteOnClose);
    window->session_ = session;

    if (session != nullptr) {
        connect(session, &RepositorySession::workingCopyStatusUpdated, window,
                &ConflictResolveWindow::onSessionWorkingCopyStatusUpdated, Qt::UniqueConnection);
        window->currentStatus_ = session->workingCopyStatus();
        if (window->currentStatus_) {
            window->refreshBatch(window->currentStatus_->conflicted());
        }
    }

    const std::vector<ConflictBatchEntry>& entries = window->conflictBatch_.entries();
    for (std::size_t i = 0; i < entries.size(); ++i) {
        if (QString::fromStdString(entries[i].path) == initialPath) {
            window->selectEntryIndex(static_cast<int>(i));
            break;
        }
    }

    window->show();
    return window;
}

void ConflictResolveWindow::refreshBatch(const std::vector<const WorkingCopyEntry*>& conflicted) {
    const std::vector<ConflictBatchEntry> before = conflictBatch_.entries();
    conflictBatch_.merge(conflicted);
    const std::vector<ConflictBatchEntry>& after = conflictBatch_.entries();

    // Auto-advance only when the row the user is *actively looking at*
    // just flipped Unresolved -> Resolved -- see refreshBatch()'s own doc
    // comment in the header for why this must not be a blanket "anything
    // resolved -> jump" rule.
    bool selectedJustResolved = false;
    if (currentEntryIndex_ >= 0 && static_cast<std::size_t>(currentEntryIndex_) < before.size() &&
        static_cast<std::size_t>(currentEntryIndex_) < after.size()) {
        selectedJustResolved =
            before[static_cast<std::size_t>(currentEntryIndex_)].state == ConflictFileState::Unresolved &&
            after[static_cast<std::size_t>(currentEntryIndex_)].state == ConflictFileState::Resolved;
    }

    rebuildRailRows();

    if (selectedJustResolved) {
        if (const std::optional<int> next = nextUnresolvedRailIndex(after, currentEntryIndex_)) {
            selectEntryIndex(*next);
        }
    } else if (currentEntryIndex_ < 0 && !after.empty()) {
        int firstUnresolved = -1;
        for (std::size_t i = 0; i < after.size(); ++i) {
            if (after[i].state == ConflictFileState::Unresolved) {
                firstUnresolved = static_cast<int>(i);
                break;
            }
        }
        selectEntryIndex(firstUnresolved >= 0 ? firstUnresolved : 0);
    }
}

void ConflictResolveWindow::rebuildRailRows() {
    railList_->blockSignals(true);
    railList_->clear();

    const std::vector<ConflictBatchEntry>& entries = conflictBatch_.entries();
    int resolvedCount = 0;
    for (std::size_t i = 0; i < entries.size(); ++i) {
        const ConflictBatchEntry& entry = entries[i];
        const bool resolved = entry.state == ConflictFileState::Resolved;
        if (resolved) {
            ++resolvedCount;
        }
        if (resolved && hideResolvedCheckbox_->isChecked()) {
            continue;
        }

        auto* item = new QListWidgetItem(QString::fromStdString(entry.path));
        item->setData(kRailUserRole, static_cast<int>(i));
        if (resolved) {
            item->setIcon(IconLoader::icon(QStringLiteral("check"), Token::Success));
            const bool resolvedHere = resolvedByThisWindow_.count(entry.path) > 0;
            item->setToolTip(resolvedHere ? QString::fromStdString(entry.path)
                                          : tr("Resolved outside this window"));
        } else {
            item->setIcon(IconLoader::icon(QStringLiteral("alert-triangle"), Token::Warning));
            const QString token = conflictKindShortToken(entry.kind);
            item->setToolTip(token.isEmpty() ? QString::fromStdString(entry.path)
                                              : QStringLiteral("%1 (%2)").arg(
                                                    QString::fromStdString(entry.path), token));
        }
        railList_->addItem(item);

        if (static_cast<int>(i) == currentEntryIndex_) {
            railList_->setCurrentItem(item);
        }
    }
    railList_->blockSignals(false);

    progressLabel_->setText(
        tr("%1 / %2 resolved").arg(resolvedCount).arg(static_cast<int>(entries.size())));
}

void ConflictResolveWindow::selectEntryIndex(int index) {
    const std::vector<ConflictBatchEntry>& entries = conflictBatch_.entries();
    if (index < 0 || static_cast<std::size_t>(index) >= entries.size()) {
        return;
    }
    currentEntryIndex_ = index;

    for (int row = 0; row < railList_->count(); ++row) {
        QListWidgetItem* item = railList_->item(row);
        if (item->data(kRailUserRole).toInt() == index) {
            railList_->blockSignals(true);
            railList_->setCurrentItem(item);
            railList_->blockSignals(false);
            break;
        }
    }

    const ConflictBatchEntry& entry = entries[static_cast<std::size_t>(index)];
    // Resolved rows have dropped out of the session's conflicted() list, so
    // there is nothing to feed showEntry() -- they stay whatever panel_ last
    // rendered. A read-only view of the resolved content is deferred; see
    // the plan's rail-state table for the intended behaviour.
    if (entry.state != ConflictFileState::Unresolved || session_ == nullptr || !currentStatus_) {
        return;
    }
    for (const WorkingCopyEntry* candidate : currentStatus_->conflicted()) {
        if (candidate->path == entry.path) {
            panel_->showEntry(session_, *candidate);
            break;
        }
    }
}

void ConflictResolveWindow::onPanelResolutionSubmitted() {
    const std::vector<ConflictBatchEntry>& entries = conflictBatch_.entries();
    if (currentEntryIndex_ < 0 || static_cast<std::size_t>(currentEntryIndex_) >= entries.size()) {
        return;
    }
    // Records *intent* -- the actual Unresolved -> Resolved flip is only
    // observed once the session's workingCopyStatusUpdated() reply lands and
    // refreshBatch() re-scans, same as everywhere else state is derived from
    // conflicted() rather than assumed.
    resolvedByThisWindow_.insert(entries[static_cast<std::size_t>(currentEntryIndex_)].path);
}

void ConflictResolveWindow::onSessionWorkingCopyStatusUpdated() {
    if (session_ == nullptr) {
        return;
    }
    currentStatus_ = session_->workingCopyStatus();
    if (!currentStatus_) {
        return;
    }
    refreshBatch(currentStatus_->conflicted());
}

void ConflictResolveWindow::saveSplitterSizes() {
    QSettings settings;
    QVariantList list;
    for (int size : splitter_->sizes()) {
        list.append(size);
    }
    settings.setValue(conflictWindowSplitterKey(), list);
}

void ConflictResolveWindow::restoreSplitterSizes() {
    QSettings settings;
    const QVariant saved = settings.value(conflictWindowSplitterKey());
    if (!saved.isValid()) {
        return;
    }
    const QVariantList list = saved.toList();
    if (list.size() != splitter_->count()) {
        return;
    }
    QList<int> sizes;
    sizes.reserve(list.size());
    for (const QVariant& value : list) {
        sizes.append(value.toInt());
    }
    QSplitter* splitter = splitter_;
    QTimer::singleShot(0, splitter, [splitter, sizes] { splitter->setSizes(sizes); });
}

void ConflictResolveWindow::closeEvent(QCloseEvent* event) {
    QSettings settings;
    settings.setValue(conflictResolveWindowGeometryKey(), saveGeometry());
    QWidget::closeEvent(event);
}

}  // namespace gbm
