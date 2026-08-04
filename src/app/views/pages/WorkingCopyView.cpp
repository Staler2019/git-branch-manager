#include "app/views/pages/WorkingCopyView.h"

#include "app/bridge/RepositorySession.h"
#include "app/bridge/ThemeManager.h"
#include "app/dialogs/MessageDialogs.h"
#include "app/theme/Tokens.h"
#include "app/views/FileContentView.h"
#include "app/views/SideBySideDiffView.h"
#include "core/git/ops/CommitOps.h"
#include "core/git/ops/ConflictOps.h"
#include "core/git/ops/ResetOps.h"

#include <QCheckBox>
#include <QClipboard>
#include <QDesktopServices>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDragEnterEvent>
#include <QDragMoveEvent>
#include <QDropEvent>
#include <QFrame>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QMenu>
#include <QMessageBox>
#include <QMimeData>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSettings>
#include <QSplitter>
#include <QStackedWidget>
#include <QTabWidget>
#include <QTimer>
#include <QUrl>
#include <QVBoxLayout>
#include <QVariant>

#include <functional>

namespace gbm {

namespace {

/// Restores `splitter`'s sizes from QSettings key `window/splitters/<key>` if
/// present, then persists future changes under the same key -- mirrors
/// MainWindow::setupPersistentSplitter, duplicated locally rather than shared
/// since the two classes have no common base to hang a helper off.
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

/// "old -> new" for a rename/copy, otherwise just the path.
QString pathLabel(const WorkingCopyEntry& entry) {
    if (!entry.oldPath.empty()) {
        return QString::fromStdString(entry.oldPath) + QStringLiteral("  →  ") +
               QString::fromStdString(entry.path);
    }
    return QString::fromStdString(entry.path);
}

/// Qt::UserRole+1 on an unstaged-list item: whether it is untracked, i.e. has
/// no HEAD/index content for `git restore` to discard back to.
constexpr int kUntrackedRole = Qt::UserRole + 1;
/// Qt::UserRole+2: whether the row is a conflicted entry, rendered inline at
/// the top of the unstaged panel rather than as a plain stageable row.
constexpr int kConflictedRole = Qt::UserRole + 2;

/// Custom MIME type carrying the dragged row's repo-relative path, so a drop
/// on the opposite panel can call the same stage/unstage path a checkbox or
/// context-menu action would.
constexpr char kFilePathMimeType[] = "application/x-gbm-workingcopy-path";

/// A QListWidget whose drag/drop is repurposed for stage/unstage instead of
/// Qt's default same-widget item reordering: dragging out advertises the
/// row's path under a private MIME type, and dropping calls `onFileDropped`
/// rather than letting the base class insert/move any item. Self-drops (drag
/// started and dropped on the same list) are ignored -- see the note on
/// `onFileDropped` in WorkingCopyView::buildFilePanel.
class FileListWidget : public QListWidget {
public:
    explicit FileListWidget(QWidget* parent = nullptr) : QListWidget(parent) {
        setDragEnabled(true);
        setAcceptDrops(true);
        setDragDropMode(QAbstractItemView::DragDrop);
        setDefaultDropAction(Qt::MoveAction);
    }

    /// Called with the dropped item's repo-relative path. Left unset (no-op)
    /// until WorkingCopyView wires it up.
    std::function<void(const std::string&)> onFileDropped;

protected:
    void dragEnterEvent(QDragEnterEvent* event) override {
        if (event->source() != this && event->mimeData()->hasFormat(kFilePathMimeType)) {
            event->acceptProposedAction();
        }
    }

    void dragMoveEvent(QDragMoveEvent* event) override {
        if (event->source() != this && event->mimeData()->hasFormat(kFilePathMimeType)) {
            event->acceptProposedAction();
        }
    }

    void dropEvent(QDropEvent* event) override {
        // A file dragged onto the list it is already in would otherwise
        // re-stage/re-unstage it -- harmless for a file with only one kind of
        // pending change, but `git add` on a path that is both partially
        // staged and further modified stages that unstaged remainder too, a
        // change the user never asked for. Simplest correct answer: ignore it.
        if (event->source() == this || !event->mimeData()->hasFormat(kFilePathMimeType)) {
            event->ignore();
            return;
        }
        const std::string path =
            QString::fromUtf8(event->mimeData()->data(kFilePathMimeType)).toStdString();
        event->acceptProposedAction();
        if (onFileDropped) {
            onFileDropped(path);
        }
    }

    QMimeData* mimeData(const QList<QListWidgetItem*>& items) const override {
        auto* data = new QMimeData();
        if (!items.isEmpty()) {
            data->setData(kFilePathMimeType, items.first()->data(Qt::UserRole).toByteArray());
        }
        return data;
    }
};

QListWidgetItem* addEntry(QListWidget* list,
                          const WorkingCopyEntry& entry,
                          const QString& suffix,
                          bool untracked = false) {
    auto* item = new QListWidgetItem(pathLabel(entry) + suffix, list);
    item->setData(Qt::UserRole, QString::fromStdString(entry.path));
    item->setData(kUntrackedRole, untracked);
    return item;
}

}  // namespace

WorkingCopyView::WorkingCopyView(QWidget* parent) : QWidget(parent) {
    buildUi();
    rebuildLists();
}

WorkingCopyView::FilePanel WorkingCopyView::buildFilePanel(const QString& title) {
    FilePanel panel;

    panel.frame = new QFrame(this);
    panel.frame->setObjectName(QStringLiteral("workingCopyFilePanel"));
    auto* frameLayout = new QVBoxLayout(panel.frame);
    frameLayout->setContentsMargins(8, 8, 8, 8);

    auto* headerRow = new QHBoxLayout();
    auto* titleLabel = new QLabel(title, panel.frame);
    titleLabel->setObjectName(QStringLiteral("workingCopyPanelHeader"));
    panel.countLabel = new QLabel(QStringLiteral("0"), panel.frame);
    panel.countLabel->setStyleSheet(
        QStringLiteral("color: %1;").arg(ThemeManager::color(Token::TextTertiary).name()));
    headerRow->addWidget(titleLabel);
    headerRow->addStretch(1);
    headerRow->addWidget(panel.countLabel);
    frameLayout->addLayout(headerRow);

    panel.stack = new QStackedWidget(panel.frame);
    panel.list = new FileListWidget(panel.frame);
    panel.list->setSelectionMode(QAbstractItemView::SingleSelection);
    panel.list->setContextMenuPolicy(Qt::CustomContextMenu);
    panel.stack->addWidget(panel.list);

    auto* placeholder = new QLabel(QStringLiteral("Drop files here"), panel.frame);
    placeholder->setObjectName(QStringLiteral("workingCopyPlaceholder"));
    placeholder->setAlignment(Qt::AlignCenter);
    panel.stack->addWidget(placeholder);
    panel.stack->setCurrentWidget(placeholder);

    frameLayout->addWidget(panel.stack, 1);

    return panel;
}

void WorkingCopyView::buildUi() {
    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(6, 6, 6, 6);

    summaryLabel_ = new QLabel(tr("No repository open"), this);
    outerLayout->addWidget(summaryLabel_);

    auto* splitter = new QSplitter(Qt::Horizontal, this);
    splitter->setHandleWidth(6);
    splitter->setChildrenCollapsible(false);

    auto* leftWidget = new QWidget(splitter);
    leftWidget->setMinimumWidth(200);
    auto* leftLayout = new QVBoxLayout(leftWidget);
    leftLayout->setContentsMargins(0, 0, 0, 0);

    // Two equal panels, board-style: conflicted + unstaged/untracked entries
    // on the left, staged entries on the right. A QSplitter (not a plain
    // QHBoxLayout) so the two columns are user-resizable relative to each
    // other, matching every other divider in the app.
    auto* boardSplitter = new QSplitter(Qt::Horizontal, leftWidget);
    boardSplitter->setHandleWidth(6);
    boardSplitter->setChildrenCollapsible(false);

    const FilePanel unstagedPanel = buildFilePanel(tr("Unstaged"));
    const FilePanel stagedPanel = buildFilePanel(tr("Staged"));
    unstagedList_ = unstagedPanel.list;
    unstagedList_->setObjectName(QStringLiteral("workingCopyUnstagedList"));
    unstagedStack_ = unstagedPanel.stack;
    unstagedCountLabel_ = unstagedPanel.countLabel;
    unstagedList_->setAccessibleName(tr("Unstaged changes"));
    stagedList_ = stagedPanel.list;
    stagedList_->setObjectName(QStringLiteral("workingCopyStagedList"));
    stagedStack_ = stagedPanel.stack;
    stagedCountLabel_ = stagedPanel.countLabel;
    stagedList_->setAccessibleName(tr("Staged changes"));

    auto* unstagedColumnWidget = new QWidget(boardSplitter);
    unstagedColumnWidget->setMinimumWidth(120);
    auto* unstagedColumn = new QVBoxLayout(unstagedColumnWidget);
    unstagedColumn->setContentsMargins(0, 0, 0, 0);
    unstagedColumn->addWidget(unstagedPanel.frame, 1);
    stageAllButton_ = new QPushButton(tr("Stage All"), unstagedColumnWidget);
    stageAllButton_->setObjectName(QStringLiteral("secondaryButton"));
    unstagedColumn->addWidget(stageAllButton_);
    boardSplitter->addWidget(unstagedColumnWidget);

    auto* stagedColumnWidget = new QWidget(boardSplitter);
    stagedColumnWidget->setMinimumWidth(120);
    auto* stagedColumn = new QVBoxLayout(stagedColumnWidget);
    stagedColumn->setContentsMargins(0, 0, 0, 0);
    stagedColumn->addWidget(stagedPanel.frame, 1);
    unstageAllButton_ = new QPushButton(tr("Unstage All"), stagedColumnWidget);
    unstageAllButton_->setObjectName(QStringLiteral("secondaryButton"));
    stagedColumn->addWidget(unstageAllButton_);
    boardSplitter->addWidget(stagedColumnWidget);

    boardSplitter->setStretchFactor(0, 1);
    boardSplitter->setStretchFactor(1, 1);
    leftLayout->addWidget(boardSplitter, 1);

    messageEdit_ = new QPlainTextEdit(leftWidget);
    messageEdit_->setPlaceholderText(tr("Commit message…"));
    messageEdit_->setFixedHeight(56);
    messageEdit_->setAccessibleName(tr("Commit message"));
    leftLayout->addWidget(messageEdit_);

    auto* commitRow = new QHBoxLayout();
    amendCheck_ = new QCheckBox(tr("Amend"), leftWidget);
    commitButton_ = new QPushButton(tr("Commit"), leftWidget);
    commitButton_->setObjectName(QStringLiteral("primaryButton"));
    commitButton_->setEnabled(false);
    commitRow->addWidget(amendCheck_);
    commitRow->addStretch(1);
    commitRow->addWidget(commitButton_);
    leftLayout->addLayout(commitRow);

    splitter->addWidget(leftWidget);

    diffTabs_ = new QTabWidget(splitter);
    diffTabs_->setMinimumWidth(200);
    diffTabs_->setDocumentMode(true);

    originalView_ = new FileContentView(diffTabs_);
    diffTabs_->addTab(originalView_, tr("Original (HEAD)"));

    workingTab_ = buildDiffTab(diffTabs_, /*staged=*/false);
    diffTabs_->addTab(workingTab_.stack->parentWidget(), tr("Working changes"));

    stagedTab_ = buildDiffTab(diffTabs_, /*staged=*/true);
    diffTabs_->addTab(stagedTab_.stack->parentWidget(), tr("Staged"));

    {
        QSettings settings;
        const int lastTab = settings.value(QStringLiteral("workingCopy/lastDiffTab"), 1).toInt();
        diffTabs_->setCurrentIndex(qBound(0, lastTab, diffTabs_->count() - 1));
    }
    connect(diffTabs_, &QTabWidget::currentChanged, this, [](int index) {
        QSettings settings;
        settings.setValue(QStringLiteral("workingCopy/lastDiffTab"), index);
    });

    splitter->addWidget(diffTabs_);
    splitter->setStretchFactor(0, 2);
    splitter->setStretchFactor(1, 3);

    setupPersistentSplitter(splitter, QStringLiteral("workingCopyMain"));
    setupPersistentSplitter(boardSplitter, QStringLiteral("workingCopyBoard"));

    outerLayout->addWidget(splitter, 1);

    connect(stagedList_,
            &QListWidget::itemSelectionChanged,
            this,
            &WorkingCopyView::onStagedSelectionChanged);
    connect(unstagedList_,
            &QListWidget::itemSelectionChanged,
            this,
            &WorkingCopyView::onUnstagedSelectionChanged);
    connect(
        stagedList_, &QListWidget::itemActivated, this, &WorkingCopyView::onStagedItemActivated);
    connect(unstagedList_,
            &QListWidget::itemActivated,
            this,
            &WorkingCopyView::onUnstagedItemActivated);
    connect(stagedList_, &QListWidget::itemChanged, this, &WorkingCopyView::onStagedItemChanged);
    connect(
        unstagedList_, &QListWidget::itemChanged, this, &WorkingCopyView::onUnstagedItemChanged);

    // Drag-and-drop between panels shares the exact same submission path as
    // the checkboxes and the context menus' Stage/Unstage actions -- click
    // and drag are two triggers for one action, not two implementations.
    static_cast<FileListWidget*>(stagedList_)->onFileDropped = [this](const std::string& path) {
        if (session_ != nullptr) {
            session_->stageFiles({path});
        }
    };
    static_cast<FileListWidget*>(unstagedList_)->onFileDropped = [this](const std::string& path) {
        if (session_ != nullptr) {
            session_->unstageFiles({path});
        }
    };

    connect(
        unstagedList_, &QListWidget::customContextMenuRequested, this, [this](const QPoint& pos) {
            auto* item = unstagedList_->itemAt(pos);
            if (item == nullptr || session_ == nullptr) {
                return;
            }
            if (item->data(kConflictedRole).toBool()) {
                // Conflicted rows are resolved via double-click (see
                // onConflictedItemActivated), not this menu.
                return;
            }
            const std::string path = item->data(Qt::UserRole).toString().toStdString();
            const WorkingCopyStatusPtr status = session_->workingCopyStatus();
            if (!status) {
                return;
            }
            for (const WorkingCopyEntry* entry : status->unstaged()) {
                if (entry->path == path) {
                    showUnstagedContextMenu(*entry, unstagedList_->viewport()->mapToGlobal(pos));
                    return;
                }
            }
            for (const WorkingCopyEntry* entry : status->untracked()) {
                if (entry->path == path) {
                    showUnstagedContextMenu(*entry, unstagedList_->viewport()->mapToGlobal(pos));
                    return;
                }
            }
        });
    connect(stagedList_, &QListWidget::customContextMenuRequested, this, [this](const QPoint& pos) {
        auto* item = stagedList_->itemAt(pos);
        if (item == nullptr || session_ == nullptr) {
            return;
        }
        const std::string path = item->data(Qt::UserRole).toString().toStdString();
        const WorkingCopyStatusPtr status = session_->workingCopyStatus();
        if (!status) {
            return;
        }
        for (const WorkingCopyEntry* entry : status->staged()) {
            if (entry->path == path) {
                showStagedContextMenu(*entry, stagedList_->viewport()->mapToGlobal(pos));
                return;
            }
        }
    });
    connect(stageAllButton_, &QPushButton::clicked, this, &WorkingCopyView::onStageAllClicked);
    connect(unstageAllButton_, &QPushButton::clicked, this, &WorkingCopyView::onUnstageAllClicked);
    connect(commitButton_, &QPushButton::clicked, this, &WorkingCopyView::onCommitClicked);
    connect(amendCheck_, &QCheckBox::toggled, this, [this](bool amend) {
        messageEdit_->setPlaceholderText(amend ? tr("Leave empty to keep the previous message")
                                               : tr("Commit message…"));
    });
}

WorkingCopyView::DiffTab WorkingCopyView::buildDiffTab(QWidget* parent, bool staged) {
    DiffTab tab;
    tab.staged = staged;

    auto* container = new QWidget(parent);
    auto* layout = new QVBoxLayout(container);
    layout->setContentsMargins(0, 0, 0, 0);

    tab.sideBySideToggle = new QCheckBox(tr("Side by side"), container);
    layout->addWidget(tab.sideBySideToggle, 0, Qt::AlignRight);

    tab.stack = new QStackedWidget(container);
    // Hunk- and line-level staging live on this instance's context menu; see
    // DiffView::setStagingEnabled. The side-by-side pane stays read-only here
    // (unlike DiffPage's) -- it has no equivalent context menu, so staging
    // always happens from the unified view.
    tab.diffView = new DiffView(tab.stack);
    tab.diffView->setStagingEnabled(true);
    // Fixed for this tab's lifetime, not inherited from whichever file-list
    // row is selected -- see the DiffTab comment in the header.
    tab.diffView->setShowingStagedDiff(staged);
    tab.sideBySideView = new SideBySideDiffView(tab.stack);
    tab.stack->addWidget(tab.diffView);
    tab.stack->addWidget(tab.sideBySideView);
    layout->addWidget(tab.stack, 1);

    QStackedWidget* stack = tab.stack;
    SideBySideDiffView* sideBySideView = tab.sideBySideView;
    DiffView* diffView = tab.diffView;
    connect(tab.sideBySideToggle,
            &QCheckBox::toggled,
            this,
            [stack, sideBySideView, diffView](bool sideBySide) {
                stack->setCurrentWidget(sideBySide ? static_cast<QWidget*>(sideBySideView)
                                                   : static_cast<QWidget*>(diffView));
            });
    connect(tab.diffView,
            &DiffView::applyPatchRequested,
            this,
            &WorkingCopyView::onApplyPatchRequested);

    return tab;
}

void WorkingCopyView::showDiffInTab(DiffTab& tab, std::shared_ptr<const ParsedDiff> diff) {
    tab.diffView->showDiff(diff);
    tab.sideBySideView->showDiff(std::move(diff));
}

void WorkingCopyView::clearDiffTab(const DiffTab& tab) {
    tab.diffView->clearDiff();
    tab.sideBySideView->clearDiff();
}

void WorkingCopyView::refreshTheme() {
    originalView_->refreshTheme();
    workingTab_.diffView->refreshTheme();
    workingTab_.sideBySideView->refreshTheme();
    stagedTab_.diffView->refreshTheme();
    stagedTab_.sideBySideView->refreshTheme();
}

void WorkingCopyView::setSession(RepositorySession* session) {
    if (session_ != nullptr) {
        disconnect(session_, nullptr, this, nullptr);
    }
    session_ = session;
    if (session_ != nullptr) {
        connect(session_,
                &RepositorySession::workingCopyStatusUpdated,
                this,
                &WorkingCopyView::onWorkingCopyStatusUpdated);
        connect(session_,
                &RepositorySession::workingCopyDiffReady,
                this,
                &WorkingCopyView::onWorkingCopyDiffReady);
        connect(session_,
                &RepositorySession::fileContentReady,
                this,
                &WorkingCopyView::onFileContentReady);
        connect(session_,
                &RepositorySession::workingCopyOperationFinished,
                this,
                &WorkingCopyView::onWorkingCopyOperationFinished);
        session_->refreshWorkingCopyStatus();
    } else {
        originalView_->clear();
        clearDiffTab(workingTab_);
        clearDiffTab(stagedTab_);
        messageEdit_->clear();
        rebuildLists();
    }
}

std::optional<WorkingCopyView::Selection> WorkingCopyView::currentSelection() const {
    if (const auto items = stagedList_->selectedItems(); !items.isEmpty()) {
        return Selection{items.first()->data(Qt::UserRole).toString().toStdString(), true};
    }
    if (const auto items = unstagedList_->selectedItems(); !items.isEmpty()) {
        return Selection{items.first()->data(Qt::UserRole).toString().toStdString(), false};
    }
    return std::nullopt;
}

void WorkingCopyView::rebuildLists() {
    // Captured before clearing, so the file the user is looking at can be
    // re-selected afterwards: a hunk staged from this file must not blank the
    // diff pane out from under them.
    const auto previous = currentSelection();

    rebuilding_ = true;
    stagedList_->blockSignals(true);
    unstagedList_->blockSignals(true);
    stagedList_->clear();
    unstagedList_->clear();

    const WorkingCopyStatusPtr status = session_ ? session_->workingCopyStatus() : nullptr;
    if (status) {
        for (const WorkingCopyEntry* entry : status->conflicted()) {
            // Text left empty: the row's content is drawn entirely by the
            // widget installed below via setItemWidget, same as the commit
            // list's inline expansion panel (MainWindow::buildCommitExpansionPanel).
            auto* item = new QListWidgetItem(QString(), unstagedList_);
            item->setData(Qt::UserRole, QString::fromStdString(entry->path));
            item->setData(kConflictedRole, true);
            // Not stageable and not draggable until resolved: a checkbox or
            // a drop would otherwise try to stage a still-conflicted path.
            item->setFlags(item->flags() & ~(Qt::ItemIsUserCheckable | Qt::ItemIsDragEnabled));

            auto* row = new QWidget(unstagedList_);
            auto* rowLayout = new QVBoxLayout(row);
            rowLayout->setContentsMargins(4, 2, 4, 2);
            rowLayout->setSpacing(0);
            rowLayout->addWidget(new QLabel(pathLabel(*entry), row));
            auto* conflictLabel = new QLabel(tr("Conflicted — resolve before staging"), row);
            conflictLabel->setStyleSheet(
                QStringLiteral("color: %1;").arg(ThemeManager::color(Token::Danger).name()));
            rowLayout->addWidget(conflictLabel);
            unstagedList_->setItemWidget(item, row);
        }
        for (const WorkingCopyEntry* entry : status->staged()) {
            auto* item = addEntry(stagedList_, *entry, QString());
            item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
            item->setCheckState(Qt::Checked);
        }
        for (const WorkingCopyEntry* entry : status->unstaged()) {
            auto* item = addEntry(unstagedList_, *entry, QString());
            item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
            item->setCheckState(Qt::Unchecked);
        }
        for (const WorkingCopyEntry* entry : status->untracked()) {
            auto* item = addEntry(unstagedList_, *entry, tr("  (untracked)"), true);
            item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
            item->setCheckState(Qt::Unchecked);
        }
    }

    stagedList_->blockSignals(false);
    unstagedList_->blockSignals(false);
    rebuilding_ = false;

    bool reselected = false;
    if (previous) {
        for (QListWidget* list : {stagedList_, unstagedList_}) {
            for (int row = 0; row < list->count(); ++row) {
                if (list->item(row)->data(Qt::UserRole).toString().toStdString() ==
                    previous->path) {
                    list->setCurrentItem(list->item(row));
                    reselected = true;
                    break;
                }
            }
            if (reselected) {
                break;
            }
        }
    }
    if (previous && !reselected) {
        originalView_->clear();
        clearDiffTab(workingTab_);
        clearDiffTab(stagedTab_);
    }

    unstagedStack_->setCurrentIndex(unstagedList_->count() > 0 ? 0 : 1);
    stagedStack_->setCurrentIndex(stagedList_->count() > 0 ? 0 : 1);
    unstagedCountLabel_->setText(QString::number(unstagedList_->count()));
    stagedCountLabel_->setText(QString::number(stagedList_->count()));

    const bool hasConflicts = status && !status->conflicted().empty();

    if (!status) {
        summaryLabel_->setText(tr("No repository open"));
    } else if (status->isClean()) {
        summaryLabel_->setText(tr("No changes"));
    } else {
        summaryLabel_->setText(
            tr("%1 staged, %2 to review").arg(stagedList_->count()).arg(unstagedList_->count()));
    }

    const int conflictedCount = status ? static_cast<int>(status->conflicted().size()) : 0;
    commitButton_->setEnabled(stagedList_->count() > 0 && !hasConflicts);
    stageAllButton_->setEnabled(unstagedList_->count() > conflictedCount);
    unstageAllButton_->setEnabled(stagedList_->count() > 0);
}

void WorkingCopyView::refreshSelectedDiff() {
    if (session_ == nullptr) {
        return;
    }
    const auto selection = currentSelection();
    if (!selection) {
        originalView_->clear();
        clearDiffTab(workingTab_);
        clearDiffTab(stagedTab_);
        return;
    }
    originalView_->showMessage(tr("Loading…"));
    workingTab_.diffView->showMessage(tr("Loading changes…"));
    workingTab_.sideBySideView->showMessage(tr("Loading changes…"));
    stagedTab_.diffView->showMessage(tr("Loading changes…"));
    stagedTab_.sideBySideView->showMessage(tr("Loading changes…"));
    // Both diffs are requested regardless of which list the selection came
    // from: the two tabs are fixed comparisons (work-tree-vs-index,
    // index-vs-HEAD), not a mirror of whichever list happens to be selected --
    // a file selected in the unstaged list can still have staged content from
    // an earlier partial stage, and vice versa.
    session_->requestWorkingCopyDiff(selection->path, false);
    session_->requestWorkingCopyDiff(selection->path, true);
    session_->requestFileContent(selection->path, "HEAD");
}

void WorkingCopyView::onWorkingCopyStatusUpdated() {
    rebuildLists();
}

void WorkingCopyView::onWorkingCopyDiffReady(QString path,
                                             bool staged,
                                             std::shared_ptr<const ParsedDiff> diff) {
    const auto selection = currentSelection();
    if (!selection || QString::fromStdString(selection->path) != path) {
        // The user moved on before this arrived. Note: no longer gated on
        // `selection->staged` -- both the working-changes and staged diffs
        // are fetched for whichever file is selected, regardless of which
        // list it was selected from (see refreshSelectedDiff).
        return;
    }
    showDiffInTab(staged ? stagedTab_ : workingTab_, std::move(diff));
}

void WorkingCopyView::onFileContentReady(QString path,
                                         QString revision,
                                         QString content,
                                         bool exists) {
    const auto selection = currentSelection();
    if (!selection || QString::fromStdString(selection->path) != path ||
        revision != QStringLiteral("HEAD")) {
        // The user moved on before this arrived.
        return;
    }
    if (exists) {
        originalView_->showContent(content);
    } else {
        // A brand-new untracked file (or one added since HEAD) has no HEAD
        // side to show -- a placeholder beats erroring on a perfectly normal
        // state.
        originalView_->showMessage(tr("This file does not exist yet at HEAD"));
    }
}

void WorkingCopyView::onWorkingCopyOperationFinished(const OperationOutcome& outcome) {
    if (outcome.succeeded) {
        emit statusMessage(QString::fromStdString(outcome.summary));
        // CommitOperation::describe() is exactly "Commit" or "Amend commit";
        // no other working-copy operation's summary starts that way.
        if (outcome.summary.rfind("Commit", 0) == 0 || outcome.summary.rfind("Amend", 0) == 0) {
            messageEdit_->clear();
            amendCheck_->setChecked(false);
        }
        return;
    }
    if (outcome.error) {
        emit errorOccurred(QString::fromStdString(outcome.summary), *outcome.error);
    }
}

void WorkingCopyView::onStagedSelectionChanged() {
    if (stagedList_->selectedItems().isEmpty()) {
        return;
    }
    unstagedList_->blockSignals(true);
    unstagedList_->clearSelection();
    unstagedList_->blockSignals(false);
    refreshSelectedDiff();
}

void WorkingCopyView::onUnstagedSelectionChanged() {
    if (unstagedList_->selectedItems().isEmpty()) {
        return;
    }
    stagedList_->blockSignals(true);
    stagedList_->clearSelection();
    stagedList_->blockSignals(false);
    refreshSelectedDiff();
}

void WorkingCopyView::onStagedItemActivated(QListWidgetItem* item) {
    if (session_ == nullptr || item == nullptr) {
        return;
    }
    session_->unstageFiles({item->data(Qt::UserRole).toString().toStdString()});
}

void WorkingCopyView::onUnstagedItemActivated(QListWidgetItem* item) {
    if (session_ == nullptr || item == nullptr) {
        return;
    }
    if (item->data(kConflictedRole).toBool()) {
        onConflictedItemActivated(item);
        return;
    }
    session_->stageFiles({item->data(Qt::UserRole).toString().toStdString()});
}

void WorkingCopyView::onUnstagedItemChanged(QListWidgetItem* item) {
    if (rebuilding_ || session_ == nullptr || item == nullptr) {
        return;
    }
    // Checking the box stages the file, the same path as a drop onto the
    // staged panel or "Stage file" on the context menu. Unchecking is a
    // no-op: the row leaves this panel (and the checkbox with it) once the
    // next status refresh reflects the stage, rather than trying to "unstage
    // an unstaged file" here.
    if (item->checkState() == Qt::Checked) {
        session_->stageFiles({item->data(Qt::UserRole).toString().toStdString()});
    }
}

void WorkingCopyView::onStagedItemChanged(QListWidgetItem* item) {
    if (rebuilding_ || session_ == nullptr || item == nullptr) {
        return;
    }
    if (item->checkState() == Qt::Unchecked) {
        session_->unstageFiles({item->data(Qt::UserRole).toString().toStdString()});
    }
}

void WorkingCopyView::onConflictedItemActivated(QListWidgetItem* item) {
    if (session_ == nullptr || item == nullptr) {
        return;
    }
    const std::string path = item->data(Qt::UserRole).toString().toStdString();
    const WorkingCopyStatusPtr status = session_->workingCopyStatus();
    if (!status) {
        return;
    }
    for (const WorkingCopyEntry* entry : status->conflicted()) {
        if (entry->path == path) {
            openConflictResolutionDialog(*entry);
            return;
        }
    }
}

void WorkingCopyView::showUnstagedContextMenu(const WorkingCopyEntry& entry,
                                              const QPoint& globalPos) {
    if (session_ == nullptr) {
        return;
    }
    const QString qpath = QString::fromStdString(entry.path);

    QMenu menu(this);
    QAction* stageAction = menu.addAction(tr("Stage file"));
    QAction* viewDiffAction = menu.addAction(tr("View diff"));
    QAction* openFileAction = menu.addAction(tr("Open file"));
    menu.addSeparator();
    QAction* copyPathAction = menu.addAction(tr("Copy path"));
    menu.addSeparator();
    QAction* discardAction = menu.addAction(tr("Discard changes…"));
    // `git restore` has nothing to discard an untracked file back to -- there
    // is no HEAD/index content for it -- so the action stays visible (the
    // menu's shape matches the design regardless of file kind) but disabled,
    // same convention SidebarPanel uses for an action that would just fail.
    if (entry.untracked) {
        discardAction->setEnabled(false);
        discardAction->setToolTip(
            tr("Not supported: an untracked file has no committed content to restore"));
    }

    QAction* chosen = menu.exec(globalPos);
    if (chosen == nullptr) {
        return;
    }

    if (chosen == stageAction) {
        session_->stageFiles({entry.path});
    } else if (chosen == viewDiffAction) {
        emit viewFileDiffRequested(qpath, false);
    } else if (chosen == openFileAction) {
        const QString fullPath =
            QString::fromStdString((session_->paths().workDir() / entry.path).string());
        QDesktopServices::openUrl(QUrl::fromLocalFile(fullPath));
    } else if (chosen == copyPathAction) {
        QGuiApplication::clipboard()->setText(qpath);
    } else if (chosen == discardAction) {
        const bool confirmed =
            dialogs::confirm(this,
                             tr("Discard changes?"),
                             tr("This permanently discards your uncommitted changes "
                                "to \"%1\".")
                                 .arg(qpath),
                             tr("Discard"),
                             /*destructive=*/true);
        if (!confirmed) {
            return;
        }
        RestoreRequest request;
        request.paths = {entry.path};
        request.staged = false;
        session_->restorePaths(request);
    }
}

void WorkingCopyView::showStagedContextMenu(const WorkingCopyEntry& entry,
                                            const QPoint& globalPos) {
    if (session_ == nullptr) {
        return;
    }
    const QString qpath = QString::fromStdString(entry.path);

    QMenu menu(this);
    QAction* unstageAction = menu.addAction(tr("Unstage file"));
    QAction* viewDiffAction = menu.addAction(tr("View diff"));
    QAction* openFileAction = menu.addAction(tr("Open file"));
    menu.addSeparator();
    QAction* copyPathAction = menu.addAction(tr("Copy path"));

    QAction* chosen = menu.exec(globalPos);
    if (chosen == nullptr) {
        return;
    }

    if (chosen == unstageAction) {
        session_->unstageFiles({entry.path});
    } else if (chosen == viewDiffAction) {
        emit viewFileDiffRequested(qpath, true);
    } else if (chosen == openFileAction) {
        const QString fullPath =
            QString::fromStdString((session_->paths().workDir() / entry.path).string());
        QDesktopServices::openUrl(QUrl::fromLocalFile(fullPath));
    } else if (chosen == copyPathAction) {
        QGuiApplication::clipboard()->setText(qpath);
    }
}

void WorkingCopyView::openConflictResolutionDialog(const WorkingCopyEntry& entry) {
    if (session_ == nullptr) {
        return;
    }

    QDialog dialog(this);
    dialog.setWindowTitle(tr("Resolve conflict — %1").arg(QString::fromStdString(entry.path)));
    auto* layout = new QVBoxLayout(&dialog);

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
    if (!kindText.isEmpty()) {
        layout->addWidget(new QLabel(kindText, &dialog));
    }

    auto* panesLayout = new QHBoxLayout();
    auto makePane = [&](const QString& title) {
        auto* container = new QWidget(&dialog);
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
    QPlainTextEdit* ancestorEdit = makePane(tr("Common ancestor"));
    QPlainTextEdit* oursEdit = makePane(tr("Mine (ours)"));
    QPlainTextEdit* theirsEdit = makePane(tr("Theirs"));
    if (entry.ancestorBlob.empty()) {
        ancestorEdit->setPlainText(tr("(no common ancestor)"));
    }
    if (entry.oursBlob.empty()) {
        oursEdit->setPlainText(tr("(deleted on this side)"));
    }
    if (entry.theirsBlob.empty()) {
        theirsEdit->setPlainText(tr("(deleted on the other side)"));
    }
    layout->addLayout(panesLayout, 1);

    // Scoped to the dialog's lifetime via the context object: if the request's
    // reply arrives after the dialog has already closed, Qt drops the
    // connection rather than calling back into destroyed widgets.
    const QString path = QString::fromStdString(entry.path);
    connect(session_,
            &RepositorySession::conflictSidesReady,
            &dialog,
            [path, ancestorEdit, oursEdit, theirsEdit](
                QString readyPath, QString ancestor, QString ours, QString theirs) {
                if (readyPath != path) {
                    return;
                }
                ancestorEdit->setPlainText(ancestor);
                oursEdit->setPlainText(ours);
                theirsEdit->setPlainText(theirs);
            });
    session_->requestConflictSides(
        entry.path, entry.ancestorBlob, entry.oursBlob, entry.theirsBlob);

    auto* buttonRow = new QHBoxLayout();
    auto* takeOursButton = new QPushButton(tr("Take Mine"), &dialog);
    auto* takeTheirsButton = new QPushButton(tr("Take Theirs"), &dialog);
    auto* markResolvedButton = new QPushButton(tr("Mark Resolved"), &dialog);
    auto* cancelButton = new QPushButton(tr("Cancel"), &dialog);
    buttonRow->addWidget(takeOursButton);
    buttonRow->addWidget(takeTheirsButton);
    buttonRow->addWidget(markResolvedButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(cancelButton);
    layout->addLayout(buttonRow);

    connect(takeOursButton, &QPushButton::clicked, &dialog, [&dialog] { dialog.done(1); });
    connect(takeTheirsButton, &QPushButton::clicked, &dialog, [&dialog] { dialog.done(2); });
    connect(markResolvedButton, &QPushButton::clicked, &dialog, [&dialog] { dialog.done(3); });
    connect(cancelButton, &QPushButton::clicked, &dialog, [&dialog] { dialog.done(0); });

    dialog.resize(720, 420);
    const int result = dialog.exec();
    if (result == 0 || session_ == nullptr) {
        return;
    }

    ResolveConflictRequest request;
    request.path = entry.path;
    request.oursBlobMissing = entry.oursBlob.empty();
    request.theirsBlobMissing = entry.theirsBlob.empty();
    switch (result) {
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
}

void WorkingCopyView::onStageAllClicked() {
    if (session_ == nullptr) {
        return;
    }
    std::vector<std::string> paths;
    paths.reserve(static_cast<std::size_t>(unstagedList_->count()));
    for (int row = 0; row < unstagedList_->count(); ++row) {
        QListWidgetItem* item = unstagedList_->item(row);
        if (item->data(kConflictedRole).toBool()) {
            continue;
        }
        paths.push_back(item->data(Qt::UserRole).toString().toStdString());
    }
    if (!paths.empty()) {
        session_->stageFiles(std::move(paths));
    }
}

void WorkingCopyView::onUnstageAllClicked() {
    if (session_ == nullptr) {
        return;
    }
    std::vector<std::string> paths;
    paths.reserve(static_cast<std::size_t>(stagedList_->count()));
    for (int row = 0; row < stagedList_->count(); ++row) {
        paths.push_back(stagedList_->item(row)->data(Qt::UserRole).toString().toStdString());
    }
    if (!paths.empty()) {
        session_->unstageFiles(std::move(paths));
    }
}

void WorkingCopyView::onCommitClicked() {
    if (session_ == nullptr) {
        return;
    }
    CommitRequest request;
    request.message = messageEdit_->toPlainText().toStdString();
    request.amend = amendCheck_->isChecked();
    session_->commitChanges(request);
}

void WorkingCopyView::onApplyPatchRequested(QString patch, bool reverse) {
    if (session_ == nullptr) {
        return;
    }
    session_->applyPatch(patch.toStdString(), reverse);
}

}  // namespace gbm
