#include "app/views/ConflictResolveWindow.h"

#include "app/bridge/ConflictBatchStore.h"
#include "app/bridge/RepositorySession.h"
#include "app/theme/IconLoader.h"
#include "app/theme/Tokens.h"
#include "app/views/ConflictResolvePanel.h"

#include <QCheckBox>
#include <QCloseEvent>
#include <QHBoxLayout>
#include <QKeySequence>
#include <QLabel>
#include <QListWidget>
#include <QMessageBox>
#include <QPushButton>
#include <QSettings>
#include <QShortcut>
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
    // C13: modal for the whole time this window is open -- see the class
    // comment for why this stays a QWidget rather than becoming a QDialog.
    setWindowModality(Qt::ApplicationModal);

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
    // panel_->cancelled() is deliberately left unconnected: a single file's
    // cancel no longer means "close the whole window" once several files
    // share one window. What "cancel" means at the window level is the
    // cancelButton_/pendingExit_ machinery below instead.
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

    // Design B1's three explicit exits. Each button records its intent in
    // pendingExit_ and then just calls close() -- closeEvent() is the one
    // place that decides whether to confirm and what to persist, so there
    // is exactly one confirmation dialog per close attempt, not one per
    // button plus one in closeEvent().
    cancelButton_ = new QPushButton(tr("Cancel"), this);
    cancelButton_->setObjectName(QStringLiteral("conflictWindowCancelButton"));
    connect(cancelButton_, &QPushButton::clicked, this, [this] {
        pendingExit_ = PendingExit::Cancel;
        close();
    });

    saveProgressButton_ = new QPushButton(tr("Save Current Progress"), this);
    saveProgressButton_->setObjectName(QStringLiteral("conflictWindowSaveProgressButton"));
    connect(saveProgressButton_, &QPushButton::clicked, this, [this] {
        pendingExit_ = PendingExit::SaveProgress;
        close();
    });

    finishAllButton_ = new QPushButton(tr("Apply All and Finish"), this);
    finishAllButton_->setObjectName(QStringLiteral("conflictWindowFinishAllButton"));
    finishAllButton_->setDefault(true);
    connect(finishAllButton_, &QPushButton::clicked, this, [this] {
        pendingExit_ = PendingExit::FinishAll;
        close();
    });

    auto* exitRow = new QHBoxLayout();
    exitRow->addStretch(1);
    exitRow->addWidget(cancelButton_);
    exitRow->addWidget(saveProgressButton_);
    exitRow->addWidget(finishAllButton_);

    // Esc must reach this window even while middleEdit_ (a QPlainTextEdit)
    // has focus. A WindowShortcut fires ahead of the focused widget's own
    // key handling for keys that widget doesn't itself reserve via
    // ShortcutOverride -- Escape has no text-editing meaning, unlike
    // Left/Right/Backspace (see the C8 hazard those needed a workaround
    // for), so no such workaround is needed here.
    auto* escapeShortcut = new QShortcut(QKeySequence(Qt::Key_Escape), this);
    escapeShortcut->setContext(Qt::WindowShortcut);
    connect(escapeShortcut, &QShortcut::activated, this, [this] {
        pendingExit_ = PendingExit::Cancel;
        close();
    });

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->addWidget(splitter_, 1);
    layout->addLayout(exitRow);

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
    updateExitButtonsEnabled();
}

ConflictResolveWindow* ConflictResolveWindow::openFor(QWidget* parent, RepositorySession* session,
                                                       const QString& initialPath) {
    auto* window = new ConflictResolveWindow(parent);
    window->setAttribute(Qt::WA_DeleteOnClose);
    window->session_ = session;

    if (session != nullptr) {
        // Design B2: resume whatever batch (if any) was saved for this exact
        // operation before the first live merge() -- see
        // ConflictBatchStore::operationFingerprint()'s own comment on what
        // "exact" means here and its accepted trade-off.
        const std::string fingerprint =
            ConflictBatchStore::operationFingerprint(session->paths(), session->state());
        window->conflictBatch_ = ConflictBatchStore::load(session->paths(), fingerprint);

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

    // Design B2: persist after every merge so the batch survives an app
    // restart mid-operation. Cleared instead once every tracked file is
    // resolved *and* the sequencer operation itself has actually ended
    // (isClean()) -- allResolved() alone isn't enough, since a rebase can
    // finish one step fully resolved and then immediately surface a fresh
    // conflict on the next commit it replays.
    if (session_ != nullptr) {
        if (conflictBatch_.allResolved() && session_->state().isClean()) {
            ConflictBatchStore::clear(session_->paths());
        } else {
            ConflictBatchStore::save(session_->paths(), conflictBatch_);
        }
    }

    updateExitButtonsEnabled();
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
    // The titlebar close button / Alt+F4 / Cmd+W all skip every button
    // above, so pendingExit_ is still None when they trigger this --
    // treating that the same as an explicit Cancel is exactly "Esc 與視窗
    // 關閉鈕都對應「取消」" from the plan.
    const PendingExit exit = pendingExit_ == PendingExit::None ? PendingExit::Cancel : pendingExit_;
    pendingExit_ = PendingExit::None;

    // 全部套用並完成 is only ever enabled once conflictBatch_.allResolved()
    // (see updateExitButtonsEnabled()), which means whatever file panel_ has
    // loaded is already resolved and submitted -- nothing to confirm. Every
    // other exit (including the titlebar/Esc fallback above) can be closing
    // out from under an in-progress file, so those still ask.
    if (exit != PendingExit::FinishAll && !confirmDiscardCurrentFileProgressIfAny()) {
        event->ignore();
        return;
    }

    QSettings settings;
    settings.setValue(conflictResolveWindowGeometryKey(), saveGeometry());
    QWidget::closeEvent(event);
}

void ConflictResolveWindow::updateExitButtonsEnabled() {
    saveProgressButton_->setEnabled(conflictBatch_.resolvedCount() > 0);
    finishAllButton_->setEnabled(conflictBatch_.allResolved());
}

bool ConflictResolveWindow::confirmDiscardCurrentFileProgressIfAny() {
    if (panel_ == nullptr || !panel_->hasUnsavedProgress()) {
        return true;
    }
    const auto answer = QMessageBox::question(
        this, tr("Discard unsaved progress?"),
        tr("The file you're currently working on has choices that haven't been saved yet. "
           "Closing now will discard them -- files you've already saved are not affected. "
           "Continue?"),
        QMessageBox::Yes | QMessageBox::Cancel, QMessageBox::Cancel);
    return answer == QMessageBox::Yes;
}

}  // namespace gbm
