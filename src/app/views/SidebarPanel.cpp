#include "app/views/SidebarPanel.h"

#include "app/bridge/RepositorySession.h"
#include "app/bridge/ThemeManager.h"
#include "app/dialogs/MessageDialogs.h"
#include "app/models/RefRowDelegate.h"
#include "app/models/RefTreeModel.h"
#include "app/models/RepoListModel.h"
#include "app/models/SidebarRowDelegate.h"
#include "app/views/TerminalLauncher.h"
#include "core/git/RefStore.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/git/ops/RebaseOps.h"
#include "core/git/ops/RemoteOps.h"
#include "core/git/ops/StashOps.h"
#include "core/git/ops/TagOps.h"

#include <QAction>
#include <QClipboard>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QIcon>
#include <QInputDialog>
#include <QKeySequence>
#include <QLabel>
#include <QLineEdit>
#include <QListView>
#include <QListWidget>
#include <QMenu>
#include <QMessageBox>
#include <QPainter>
#include <QPixmap>
#include <QSet>
#include <QSettings>
#include <QSplitter>
#include <QStringList>
#include <QTimer>
#include <QTreeView>
#include <QUrl>
#include <QVBoxLayout>
#include <QVariant>

#include <functional>
#include <utility>

namespace gbm {

namespace {

/// Restores `splitter`'s sizes from QSettings key `window/splitters/<key>` if
/// present, then persists future changes under the same key. Duplicated
/// (rather than shared) alongside MainWindow's and WorkingCopyView's copies
/// of the same few lines -- the three classes have no common base to hang a
/// shared helper off, and this is small enough that a new home for it is not
/// worth the indirection.
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

/// A small hand-drawn magnifying glass, theme-tinted at paint time.
///
/// The design names real Lucide SVGs for every icon in the app; this sandbox
/// does have outbound network access (checked: `curl` reaches
/// raw.githubusercontent.com), unlike what Phase 0/1 reported for theirs. A
/// bundled Lucide `search.svg` would still need `Qt6::Svg` linked plus
/// runtime re-tinting (its `stroke="currentColor"` renders black regardless
/// of theme, which is wrong on the dark themes) to look right in all three
/// themes -- a new build dependency and a second icon pipeline for exactly
/// one icon. Drawing the same glyph by hand is a few lines, needs nothing new
/// in CMake, and is trivially theme-correct. See the report for the tradeoff.
QIcon makeSearchIcon(const QColor& color) {
    const int size = 16;
    QPixmap pixmap(size, size);
    pixmap.fill(Qt::transparent);
    QPainter painter(&pixmap);
    painter.setRenderHint(QPainter::Antialiasing, true);
    QPen pen(color, 1.6);
    painter.setPen(pen);
    painter.setBrush(Qt::NoBrush);
    painter.drawEllipse(QRectF(2.0, 2.0, 8.0, 8.0));
    painter.drawLine(QPointF(9.5, 9.5), QPointF(13.5, 13.5));
    painter.end();
    return QIcon(pixmap);
}

/// The minimum acceptable danger treatment per the design brief: since Qt
/// Style Sheets cannot select one `QMenu::item` out of many (there is no
/// dynamic-property matching against the originating `QAction`, only against
/// the `QMenu` widget itself), this tints the action's icon instead of its
/// text. A `QWidgetAction`-wrapped `QLabel` would colour the text directly,
/// but loses the hover-highlight and keyboard-navigation behaviour every
/// other item gets for free from the style; that regression was judged worse
/// than an icon-only treatment for a first pass. Noted in the report.
void markDanger(QAction* action) {
    const int size = 10;
    QPixmap pixmap(size, size);
    pixmap.fill(Qt::transparent);
    QPainter painter(&pixmap);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setBrush(ThemeManager::color(Token::Danger));
    painter.setPen(Qt::NoPen);
    painter.drawEllipse(QRectF(1.0, 1.0, size - 2.0, size - 2.0));
    painter.end();
    action->setIcon(QIcon(pixmap));
}

/// Splits "origin/feature/x" into {"origin", "feature/x"} using the actual
/// configured remote names rather than guessing at the first path segment --
/// a branch literally named "origin/foo" on a differently-named remote must
/// not be misparsed.
std::pair<std::string, std::string> splitRemoteBranch(const std::string& shortName,
                                                      const RemoteListPtr& remotes) {
    if (remotes) {
        for (const RemoteInfo& remote : *remotes) {
            const std::string prefix = remote.name + "/";
            if (shortName.rfind(prefix, 0) == 0) {
                return {remote.name, shortName.substr(prefix.size())};
            }
        }
    }
    // Fallback: first path segment, if no configured remote matched.
    const auto slash = shortName.find('/');
    if (slash == std::string::npos) {
        return {shortName, {}};
    }
    return {shortName.substr(0, slash), shortName.substr(slash + 1)};
}

}  // namespace

SidebarPanel::SidebarPanel(RepoListModel* repoModel,
                           RefTreeModel* refModel,
                           QTreeView* refView,
                           RunWithFeedbackFn runWithFeedback,
                           QWidget* parent)
    : QWidget(parent),
      repoModel_(repoModel),
      refModel_(refModel),
      refView_(refView),
      runWithFeedback_(std::move(runWithFeedback)) {
    buildUi();
}

void SidebarPanel::buildUi() {
    setMinimumWidth(220);

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);

    // --- filter -------------------------------------------------------------
    filterEdit_ = new QLineEdit(this);
    filterEdit_->setPlaceholderText(QStringLiteral("Filter…"));
    filterEdit_->setClearButtonEnabled(true);
    filterEdit_->setAccessibleName(QStringLiteral("Filter sidebar"));
    searchIconAction_ = filterEdit_->addAction(
        makeSearchIcon(ThemeManager::color(Token::TextTertiary)), QLineEdit::LeadingPosition);
    connect(filterEdit_, &QLineEdit::textChanged, this, &SidebarPanel::onFilterChanged);
    layout->addWidget(filterEdit_);

    // Repositories / Branches-Remotes-Tags / Stash are a vertical QSplitter
    // (not a plain QVBoxLayout with maximumHeight caps, as before) so all
    // three are user-resizable relative to each other. Each section's header
    // label must be wrapped together with its view in its own container
    // widget first: a QSplitter's direct children are its resizable panes, so
    // a bare header QLabel added as a splitter child would become an
    // independently draggable sliver of its own rather than staying attached
    // to the view below it.
    auto* sectionSplitter = new QSplitter(Qt::Vertical, this);
    sectionSplitter->setHandleWidth(6);
    sectionSplitter->setChildrenCollapsible(false);

    auto addSectionHeader = [](QWidget* parent, QVBoxLayout* sectionLayout, const QString& text) {
        auto* label = new QLabel(text.toUpper(), parent);
        label->setObjectName(QStringLiteral("sidebarSectionHeader"));
        label->setFont(ThemeManager::sectionHeaderFont());
        sectionLayout->addWidget(label);
    };

    // --- Repositories ---------------------------------------------------------
    auto* repoSection = new QWidget(sectionSplitter);
    repoSection->setMinimumHeight(60);
    auto* repoSectionLayout = new QVBoxLayout(repoSection);
    repoSectionLayout->setContentsMargins(0, 0, 0, 0);
    repoSectionLayout->setSpacing(0);
    addSectionHeader(repoSection, repoSectionLayout, QStringLiteral("Repositories"));
    repoListView_ = new QListView(repoSection);
    repoListView_->setObjectName(QStringLiteral("gbmRepoList"));
    repoListView_->setAccessibleName(QStringLiteral("Repositories"));
    repoListView_->setModel(repoModel_);
    repoListView_->setModelColumn(RepoListModel::ColumnName);
    repoListView_->setItemDelegate(
        new SidebarRowDelegate(SidebarRowDelegate::Kind::Repository, repoListView_));
    repoListView_->setUniformItemSizes(true);
    repoListView_->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(repoListView_,
            &QListView::customContextMenuRequested,
            this,
            &SidebarPanel::onRepoContextMenuRequested);
    repoSectionLayout->addWidget(repoListView_, 1);
    sectionSplitter->addWidget(repoSection);

    // --- Branches / Remotes / Tags -------------------------------------------
    // refView_/refModel_ are constructed and owned by MainWindow; this panel
    // only takes over their layout position and context-menu policy.
    auto* refSection = new QWidget(sectionSplitter);
    refSection->setMinimumHeight(80);
    auto* refSectionLayout = new QVBoxLayout(refSection);
    refSectionLayout->setContentsMargins(0, 0, 0, 0);
    refSectionLayout->setSpacing(0);
    refView_->setParent(refSection);
    refView_->setItemDelegate(new RefRowDelegate(refView_));
    // Extended (not the QTreeView default Single) so several local branches
    // can be Ctrl/Shift-selected and deleted together; showBranchContextMenu
    // below reads the full selection, not just the clicked row.
    refView_->setSelectionMode(QAbstractItemView::ExtendedSelection);
    refView_->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(refView_,
            &QTreeView::customContextMenuRequested,
            this,
            &SidebarPanel::onRefContextMenuRequested);
    // Persist each grouping node's expand/collapse state across restarts.
    // restoreRefExpansion() (connected to modelReset below) provokes these
    // same signals while it runs; restoringRefExpansion_ tells them apart
    // from real user clicks so a restore never re-saves itself as new state.
    connect(refView_, &QTreeView::expanded, this, [this](const QModelIndex& index) {
        if (!restoringRefExpansion_) {
            saveRefExpansion(index, true);
        }
    });
    connect(refView_, &QTreeView::collapsed, this, [this](const QModelIndex& index) {
        if (!restoringRefExpansion_) {
            saveRefExpansion(index, false);
        }
    });
    connect(refModel_, &QAbstractItemModel::modelReset, this, &SidebarPanel::restoreRefExpansion);
    refSectionLayout->addWidget(refView_, 1);
    sectionSplitter->addWidget(refSection);

    // --- Stash ----------------------------------------------------------------
    auto* stashSection = new QWidget(sectionSplitter);
    stashSection->setMinimumHeight(60);
    auto* stashSectionLayout = new QVBoxLayout(stashSection);
    stashSectionLayout->setContentsMargins(0, 0, 0, 0);
    stashSectionLayout->setSpacing(0);
    addSectionHeader(stashSection, stashSectionLayout, QStringLiteral("Stash"));
    stashList_ = new QListWidget(stashSection);
    stashList_->setObjectName(QStringLiteral("gbmStashList"));
    stashList_->setAccessibleName(QStringLiteral("Stashes"));
    stashList_->setItemDelegate(
        new SidebarRowDelegate(SidebarRowDelegate::Kind::Stash, stashList_));
    stashList_->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(stashList_,
            &QListWidget::customContextMenuRequested,
            this,
            &SidebarPanel::onStashContextMenuRequested);
    stashSectionLayout->addWidget(stashList_, 1);
    sectionSplitter->addWidget(stashSection);

    // Repositories and Stash default to their old fixed 120px allowance;
    // Branches/Remotes/Tags gets the rest. setSizes() before the splitter has
    // real geometry gets recomputed from these on first resize rather than
    // honored as-is, which is fine here since that recomputation preserves
    // the same proportions.
    sectionSplitter->setSizes({120, 400, 120});
    sectionSplitter->setStretchFactor(0, 0);
    sectionSplitter->setStretchFactor(1, 1);
    sectionSplitter->setStretchFactor(2, 0);
    setupPersistentSplitter(sectionSplitter, QStringLiteral("sidebarSections"));

    layout->addWidget(sectionSplitter, 1);
}

void SidebarPanel::refreshTheme() {
    searchIconAction_->setIcon(makeSearchIcon(ThemeManager::color(Token::TextTertiary)));
}

void SidebarPanel::setSession(RepositorySession* session) {
    if (session_ != nullptr) {
        disconnect(session_, nullptr, this, nullptr);
    }
    session_ = session;
    if (session_ != nullptr) {
        connect(session_, &RepositorySession::stashesUpdated, this, &SidebarPanel::reloadStashes);
        session_->refreshStashes();
    } else {
        stashList_->clear();
    }
}

void SidebarPanel::reloadStashes() {
    stashList_->clear();
    if (session_ == nullptr) {
        return;
    }
    if (auto stashes = session_->stashes()) {
        for (const StashEntry& entry : *stashes) {
            auto* item = new QListWidgetItem(QStringLiteral("stash@{%1}  %2")
                                                 .arg(entry.index)
                                                 .arg(QString::fromStdString(entry.message)),
                                             stashList_);
            item->setData(Qt::UserRole, entry.index);
        }
    }
}

void SidebarPanel::onFilterChanged(const QString& text) {
    const QString filter = text.trimmed();
    // applyRefFilter() force-expands matching groups while a filter is active
    // (below); that is transient filtering state, not a user's deliberate
    // expand/collapse, so it must not overwrite the persisted expansion set.
    restoringRefExpansion_ = true;
    applyRefFilter(QModelIndex(), filter);
    restoringRefExpansion_ = false;

    for (int row = 0; row < repoModel_->rowCount(); ++row) {
        const QModelIndex index = repoModel_->index(row, RepoListModel::ColumnName);
        const bool visible = filter.isEmpty() || repoModel_->data(index, Qt::DisplayRole)
                                                     .toString()
                                                     .contains(filter, Qt::CaseInsensitive);
        repoListView_->setRowHidden(row, !visible);
    }

    for (int row = 0; row < stashList_->count(); ++row) {
        QListWidgetItem* item = stashList_->item(row);
        item->setHidden(!filter.isEmpty() && !item->text().contains(filter, Qt::CaseInsensitive));
    }
}

bool SidebarPanel::applyRefFilter(const QModelIndex& parent, const QString& filter) {
    bool anyVisibleChild = false;
    const int rows = refModel_->rowCount(parent);
    for (int row = 0; row < rows; ++row) {
        const QModelIndex index = refModel_->index(row, 0, parent);
        const bool childMatches = applyRefFilter(index, filter);
        const bool selfMatches = filter.isEmpty() || refModel_->data(index, Qt::DisplayRole)
                                                         .toString()
                                                         .contains(filter, Qt::CaseInsensitive);
        const bool visible = selfMatches || childMatches;
        refView_->setRowHidden(row, parent, !visible);
        if (visible && childMatches && !filter.isEmpty()) {
            refView_->expand(index);
        }
        anyVisibleChild = anyVisibleChild || visible;
    }
    return anyVisibleChild;
}

namespace {
constexpr auto kExpandedRefNodesSettingsKey = "sidebar/expandedRefNodes";
}  // namespace

QString SidebarPanel::refNodeKey(const QModelIndex& index) const {
    QStringList parts;
    for (QModelIndex cursor = index; cursor.isValid(); cursor = cursor.parent()) {
        parts.prepend(refModel_->data(cursor, Qt::DisplayRole).toString());
    }
    return parts.join(QLatin1Char('/'));
}

void SidebarPanel::saveRefExpansion(const QModelIndex& index, bool expanded) {
    const QString key = refNodeKey(index);
    if (key.isEmpty()) {
        return;
    }
    QSettings settings;
    QStringList expandedKeys =
        settings.value(QLatin1String(kExpandedRefNodesSettingsKey)).toStringList();
    expandedKeys.removeAll(key);
    if (expanded) {
        expandedKeys.append(key);
    }
    settings.setValue(QLatin1String(kExpandedRefNodesSettingsKey), expandedKeys);
}

void SidebarPanel::restoreRefExpansion() {
    QSettings settings;
    // The very first time this ever runs there is no saved value at all --
    // bootstrap the one-time default (Branches expanded; everything else,
    // including Remotes/Tags, collapsed) and persist it immediately. From
    // then on the saved list is the sole source of truth: a key's absence
    // means collapsed, full stop, with no separate "default" to fall back to
    // -- that is what lets a later explicit collapse of "Branches" stick.
    QStringList expandedKeys;
    if (settings.contains(QLatin1String(kExpandedRefNodesSettingsKey))) {
        expandedKeys = settings.value(QLatin1String(kExpandedRefNodesSettingsKey)).toStringList();
    } else {
        expandedKeys = {QStringLiteral("Branches")};
        settings.setValue(QLatin1String(kExpandedRefNodesSettingsKey), expandedKeys);
    }
    const QSet<QString> expandedSet(expandedKeys.begin(), expandedKeys.end());

    restoringRefExpansion_ = true;
    std::function<void(const QModelIndex&)> walk = [&](const QModelIndex& parent) {
        const int rows = refModel_->rowCount(parent);
        for (int row = 0; row < rows; ++row) {
            const QModelIndex index = refModel_->index(row, 0, parent);
            if (expandedSet.contains(refNodeKey(index))) {
                refView_->expand(index);
            } else {
                refView_->collapse(index);
            }
            walk(index);
        }
    };
    walk(QModelIndex());
    restoringRefExpansion_ = false;
}

void SidebarPanel::onRefContextMenuRequested(const QPoint& pos) {
    const QModelIndex index = refView_->indexAt(pos);
    if (!index.isValid() || session_ == nullptr) {
        return;
    }
    if (!refModel_->data(index, RefTreeModel::IsRefRole).toBool()) {
        return;  // A grouping node ("feature/") or section header has no menu.
    }

    // Right-clicking a row that is not already part of the current selection
    // replaces the selection (single-row, as before); right-clicking a row
    // that is already selected -- including a multi-row Ctrl/Shift selection
    // -- leaves it alone, so showBranchContextMenu below can act on the whole
    // selection instead of just the clicked row. Mirrors MainWindow's
    // onCommitContextMenuRequested.
    if (!refView_->selectionModel()->isSelected(index)) {
        refView_->selectionModel()->select(
            index, QItemSelectionModel::ClearAndSelect | QItemSelectionModel::Rows);
    }
    const QPoint globalPos = refView_->viewport()->mapToGlobal(pos);
    const auto kind =
        static_cast<RefKind>(refModel_->data(index, RefTreeModel::RefKindRole).toInt());
    switch (kind) {
        case RefKind::LocalBranch:
            showBranchContextMenu(index, globalPos);
            break;
        case RefKind::RemoteBranch:
            showRemoteBranchContextMenu(index, globalPos);
            break;
        case RefKind::Tag:
            showTagContextMenu(index, globalPos);
            break;
        default:
            break;
    }
}

void SidebarPanel::showBranchContextMenu(const QModelIndex& index, const QPoint& globalPos) {
    const QString name = refModel_->refNameAt(index);
    const bool isHead = refModel_->data(index, RefTreeModel::IsHeadRole).toBool();

    // Every action except Delete operates on the single clicked branch --
    // checkout, rename, merge-into-current, push and rebase-onto only make
    // sense for one branch at a time. Delete is the one multi-select
    // extends to (item 6), so it alone reads the full selection, filtered
    // down to real local branches other than HEAD (a HEAD branch can never
    // be deleted; a grouping/section node or a remote/tag row that happens
    // to share the selection is not a local branch at all).
    QStringList deletableNames;
    for (const QModelIndex& selected : refView_->selectionModel()->selectedRows()) {
        const bool isLocalBranch =
            refModel_->data(selected, RefTreeModel::IsRefRole).toBool() &&
            static_cast<RefKind>(refModel_->data(selected, RefTreeModel::RefKindRole).toInt()) ==
                RefKind::LocalBranch;
        if (isLocalBranch && !refModel_->data(selected, RefTreeModel::IsHeadRole).toBool()) {
            deletableNames.append(refModel_->refNameAt(selected));
        }
    }

    QMenu menu(this);
    QAction* checkoutAction = menu.addAction(QStringLiteral("Checkout %1").arg(name));
    checkoutAction->setEnabled(!isHead);
    QAction* newBranchAction = menu.addAction(QStringLiteral("New branch from here…"));
    QAction* renameAction = menu.addAction(QStringLiteral("Rename branch…"));
    menu.addSeparator();
    QAction* mergeAction = menu.addAction(QStringLiteral("Merge into current"));
    mergeAction->setEnabled(!isHead);
    QAction* rebaseAction = menu.addAction(QStringLiteral("Rebase current onto here"));
    rebaseAction->setEnabled(!isHead);
    menu.addSeparator();
    QAction* pushAction = menu.addAction(QStringLiteral("Push…"));
    QAction* copyAction = menu.addAction(QStringLiteral("Copy branch name"));
    menu.addSeparator();
    QAction* deleteAction = menu.addAction(
        deletableNames.size() > 1 ? QStringLiteral("Delete %1 branches…").arg(deletableNames.size())
                                  : QStringLiteral("Delete branch…"));
    deleteAction->setEnabled(!deletableNames.isEmpty());
    markDanger(deleteAction);

    QAction* chosen = menu.exec(globalPos);
    if (chosen == nullptr) {
        return;
    }

    if (chosen == checkoutAction) {
        emit checkoutRequested();
    } else if (chosen == newBranchAction) {
        const auto newNameResult =
            dialogs::promptText(this, QStringLiteral("New branch"), QStringLiteral("Branch name:"));
        if (!newNameResult || newNameResult->isEmpty()) {
            return;
        }
        const QString newName = *newNameResult;
        CreateBranchRequest request;
        request.name = newName.toStdString();
        request.startPoint = name.toStdString();
        emit statusMessage(QStringLiteral("Creating branch %1…").arg(newName));
        runWithFeedback_([this, request] { session_->createBranch(request); }, nullptr);
    } else if (chosen == renameAction) {
        const auto newNameResult = dialogs::promptText(
            this, QStringLiteral("Rename branch"), QStringLiteral("New name:"), name);
        if (!newNameResult || newNameResult->isEmpty() || *newNameResult == name) {
            return;
        }
        const QString newName = *newNameResult;
        RenameBranchRequest request;
        request.from = name.toStdString();
        request.to = newName.toStdString();
        emit statusMessage(QStringLiteral("Renaming %1…").arg(name));
        runWithFeedback_([this, request] { session_->renameBranch(request); }, nullptr);
    } else if (chosen == mergeAction) {
        emit mergeIntoCurrentRequested();
    } else if (chosen == rebaseAction) {
        const bool confirmed =
            dialogs::confirm(this,
                             QStringLiteral("Rebase"),
                             QStringLiteral("Rebase the current branch onto %1?").arg(name),
                             QStringLiteral("Yes"));
        if (!confirmed) {
            return;
        }
        RebaseRequest request;
        request.upstream = name.toStdString();
        emit statusMessage(QStringLiteral("Rebasing onto %1…").arg(name));
        runWithFeedback_([this, request] { session_->startRebase(request); }, nullptr);
    } else if (chosen == pushAction) {
        QStringList names;
        if (auto remotes = session_->remotes()) {
            for (const RemoteInfo& remote : *remotes) {
                names << QString::fromStdString(remote.name);
            }
        }
        if (names.isEmpty()) {
            names << QStringLiteral("origin");
        }
        const auto remoteResult = dialogs::promptChoice(
            this, QStringLiteral("Push"), QStringLiteral("Remote:"), names, 0);
        if (!remoteResult || remoteResult->isEmpty()) {
            return;
        }
        const QString remote = *remoteResult;
        PushRequest request;
        request.remoteName = remote.toStdString();
        request.branch = name.toStdString();
        emit statusMessage(QStringLiteral("Pushing %1…").arg(name));
        runWithFeedback_([this, request] { session_->pushChanges(request); }, nullptr);
    } else if (chosen == copyAction) {
        QGuiApplication::clipboard()->setText(name);
    } else if (chosen == deleteAction) {
        if (deletableNames.isEmpty()) {
            return;
        }
        const QString confirmText =
            deletableNames.size() > 1
                ? QStringLiteral("Delete %1 branches?\n\n%2")
                      .arg(deletableNames.size())
                      .arg(deletableNames.join(QStringLiteral("\n")))
                : QStringLiteral("Delete branch \"%1\"?").arg(deletableNames.first());
        const bool confirmed = dialogs::confirm(this,
                                                QStringLiteral("Delete branch?"),
                                                confirmText,
                                                QStringLiteral("Yes"),
                                                /*destructive=*/true);
        if (!confirmed) {
            return;
        }
        DeleteBranchRequest request;
        for (const QString& deletableName : deletableNames) {
            request.names.push_back(deletableName.toStdString());
        }
        emit statusMessage(deletableNames.size() > 1
                               ? QStringLiteral("Deleting %1 branches…").arg(deletableNames.size())
                               : QStringLiteral("Deleting %1…").arg(deletableNames.first()));
        runWithFeedback_([this, request] { session_->deleteBranch(request); },
                         [this, request](OperationChoice::Kind kind) mutable {
                             // The only choice DeleteBranchOperation ever offers: the branch
                             // has unmerged commits, and the user just confirmed deleting it
                             // anyway (runWithFeedback already showed that confirmation).
                             if (kind == OperationChoice::Kind::ForceDiscard) {
                                 request.force = true;
                                 runWithFeedback_(
                                     [this, request] { session_->deleteBranch(request); }, nullptr);
                             }
                         });
    }
}

void SidebarPanel::showRemoteBranchContextMenu(const QModelIndex& index, const QPoint& globalPos) {
    const QString fullShortName = refModel_->refNameAt(index);
    const auto [remoteName, branchName] =
        splitRemoteBranch(fullShortName.toStdString(), session_->remotes());

    QMenu menu(this);
    QAction* checkoutAction = menu.addAction(QStringLiteral("Checkout as new local branch…"));
    QAction* fetchAction = menu.addAction(QStringLiteral("Fetch"));
    QAction* copyAction = menu.addAction(QStringLiteral("Copy branch name"));
    menu.addSeparator();
    QAction* deleteAction = menu.addAction(QStringLiteral("Delete on remote…"));
    markDanger(deleteAction);

    QAction* chosen = menu.exec(globalPos);
    if (chosen == nullptr) {
        return;
    }

    if (chosen == checkoutAction) {
        const auto localNameResult = dialogs::promptText(this,
                                                         QStringLiteral("Checkout as new branch"),
                                                         QStringLiteral("Local branch name:"),
                                                         QString::fromStdString(branchName));
        if (!localNameResult || localNameResult->isEmpty()) {
            return;
        }
        const QString localName = *localNameResult;
        CheckoutRequest request;
        request.target = fullShortName.toStdString();
        request.createBranch = true;
        request.newBranchName = localName.toStdString();
        emit statusMessage(QStringLiteral("Checking out %1…").arg(localName));
        // checkout() emits operationFinished, not workingCopyOperationFinished
        // -- MainWindow::onOperationFinished is already connected to that
        // globally (openRepository) and reports the outcome the same way
        // runWithFeedback_ would. Routing this through runWithFeedback_
        // instead would leave its one-shot handler listening on the wrong
        // signal forever, misattributing whatever the next stash/tag/remote
        // operation's outcome is to this checkout.
        session_->checkout(request);
    } else if (chosen == fetchAction) {
        FetchRequest request;
        request.remoteName = remoteName;
        emit statusMessage(QStringLiteral("Fetching %1…").arg(QString::fromStdString(remoteName)));
        runWithFeedback_([this, request] { session_->fetchRemote(request); }, nullptr);
    } else if (chosen == copyAction) {
        QGuiApplication::clipboard()->setText(fullShortName);
    } else if (chosen == deleteAction) {
        const bool confirmed =
            dialogs::confirm(this,
                             QStringLiteral("Delete remote branch?"),
                             QStringLiteral("Delete \"%1\" on %2? This affects everyone who "
                                            "fetches from that remote.")
                                 .arg(fullShortName, QString::fromStdString(remoteName)),
                             QStringLiteral("Yes"),
                             /*destructive=*/true);
        if (!confirmed) {
            return;
        }
        DeleteBranchRequest request;
        request.names = {branchName};
        request.isRemote = true;
        request.remoteName = remoteName;
        emit statusMessage(
            QStringLiteral("Deleting %1 on %2…")
                .arg(QString::fromStdString(branchName), QString::fromStdString(remoteName)));
        runWithFeedback_([this, request] { session_->deleteBranch(request); }, nullptr);
    }
}

void SidebarPanel::showTagContextMenu(const QModelIndex& index, const QPoint& globalPos) {
    const QString name = refModel_->refNameAt(index);

    QMenu menu(this);
    QAction* checkoutAction = menu.addAction(QStringLiteral("Checkout tag (detached)"));
    QAction* pushAction = menu.addAction(QStringLiteral("Push tag…"));
    QAction* copyAction = menu.addAction(QStringLiteral("Copy tag name"));
    menu.addSeparator();
    QAction* deleteAction = menu.addAction(QStringLiteral("Delete tag…"));
    markDanger(deleteAction);

    QAction* chosen = menu.exec(globalPos);
    if (chosen == nullptr) {
        return;
    }

    if (chosen == checkoutAction) {
        CheckoutRequest request;
        request.target = name.toStdString();
        request.detach = true;
        emit statusMessage(QStringLiteral("Checking out %1 (detached)…").arg(name));
        // See the comment on the equivalent call in
        // showRemoteBranchContextMenu: checkout() emits operationFinished, not
        // workingCopyOperationFinished, so this bypasses runWithFeedback_
        // rather than mis-wiring its one-shot handler to a signal that never
        // fires for this call.
        session_->checkout(request);
    } else if (chosen == pushAction) {
        QStringList names;
        if (auto remotes = session_->remotes()) {
            for (const RemoteInfo& remote : *remotes) {
                names << QString::fromStdString(remote.name);
            }
        }
        if (names.isEmpty()) {
            names << QStringLiteral("origin");
        }
        const auto remoteResult = dialogs::promptChoice(
            this, QStringLiteral("Push tag"), QStringLiteral("Remote:"), names, 0);
        if (!remoteResult || remoteResult->isEmpty()) {
            return;
        }
        const QString remote = *remoteResult;
        PushTagRequest request;
        request.remoteName = remote.toStdString();
        request.name = name.toStdString();
        emit statusMessage(QStringLiteral("Pushing tag %1…").arg(name));
        runWithFeedback_([this, request] { session_->pushTag(request); }, nullptr);
    } else if (chosen == copyAction) {
        QGuiApplication::clipboard()->setText(name);
    } else if (chosen == deleteAction) {
        const bool confirmed = dialogs::confirm(this,
                                                QStringLiteral("Delete tag?"),
                                                QStringLiteral("Delete tag \"%1\"?").arg(name),
                                                QStringLiteral("Yes"),
                                                /*destructive=*/true);
        if (!confirmed) {
            return;
        }
        DeleteTagRequest request;
        request.name = name.toStdString();
        emit statusMessage(QStringLiteral("Deleting tag %1…").arg(name));
        runWithFeedback_([this, request] { session_->deleteTag(request); }, nullptr);
    }
}

void SidebarPanel::onRepoContextMenuRequested(const QPoint& pos) {
    const QModelIndex index = repoListView_->indexAt(pos);
    if (!index.isValid()) {
        return;
    }
    const QString path = repoModel_->data(index, RepoListModel::PathRole).toString();
    const bool isOpenRepo =
        session_ != nullptr && QString::fromStdString(session_->paths().workDir().string()) == path;

    QMenu menu(this);
    QAction* openRepoAction = menu.addAction(QStringLiteral("Open repository"));
    openRepoAction->setEnabled(!isOpenRepo);
    QAction* openInFileManagerAction = menu.addAction(QStringLiteral("Open in file manager"));
    QAction* openInTerminalAction = menu.addAction(QStringLiteral("Open in terminal"));
    QAction* fetchAction = menu.addAction(QStringLiteral("Fetch"));
    QAction* pullAction = menu.addAction(QStringLiteral("Pull"));
    QAction* pushAction = menu.addAction(QStringLiteral("Push"));
    pushAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+P")));
    if (!isOpenRepo) {
        const QString tip = QStringLiteral("Open this repository first to fetch, pull or push it");
        fetchAction->setEnabled(false);
        fetchAction->setToolTip(tip);
        pullAction->setEnabled(false);
        pullAction->setToolTip(tip);
        pushAction->setEnabled(false);
        pushAction->setToolTip(tip);
    }
    menu.addSeparator();
    QAction* settingsAction = menu.addAction(QStringLiteral("Repository settings"));
    settingsAction->setEnabled(isOpenRepo);
    menu.addSeparator();
    QAction* removeAction = menu.addAction(QStringLiteral("Remove from list…"));
    // DiscoveryController only supports removing a whole base folder
    // (removeBaseFolder), not one repository out of it -- there is no
    // per-repository removal to wire this to without adding that capability
    // to core, out of scope here. Disabled rather than silently dropped.
    removeAction->setEnabled(false);
    removeAction->setToolTip(
        QStringLiteral("Not supported yet: repositories can only be removed by removing their "
                       "whole base folder (File ▸ Manage base folders…)"));
    markDanger(removeAction);

    QAction* chosen = menu.exec(repoListView_->viewport()->mapToGlobal(pos));
    if (chosen == nullptr) {
        return;
    }

    if (chosen == openRepoAction) {
        emit openRepositoryRequested(index.row());
    } else if (chosen == openInFileManagerAction) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    } else if (chosen == openInTerminalAction) {
        QString error;
        if (!openTerminalAt(path, &error)) {
            dialogs::warn(this, QStringLiteral("Open in terminal"), error);
        }
    } else if (chosen == fetchAction) {
        emit statusMessage(QStringLiteral("Fetching…"));
        runWithFeedback_([this] { session_->fetchRemote(FetchRequest{}); }, nullptr);
    } else if (chosen == pullAction) {
        emit statusMessage(QStringLiteral("Pulling…"));
        runWithFeedback_([this] { session_->pullChanges(PullRequest{}); }, nullptr);
    } else if (chosen == pushAction) {
        emit statusMessage(QStringLiteral("Pushing…"));
        runWithFeedback_([this] { session_->pushChanges(PushRequest{}); }, nullptr);
    } else if (chosen == settingsAction) {
        emit repositorySettingsRequested();
    }
}

void SidebarPanel::onStashContextMenuRequested(const QPoint& pos) {
    QListWidgetItem* item = stashList_->itemAt(pos);
    if (item == nullptr || session_ == nullptr) {
        return;
    }
    const int stashIndex = item->data(Qt::UserRole).toInt();

    QMenu menu(this);
    QAction* applyAction = menu.addAction(QStringLiteral("Apply stash"));
    QAction* popAction = menu.addAction(QStringLiteral("Pop stash"));
    QAction* branchAction = menu.addAction(QStringLiteral("Create branch from stash…"));
    QAction* diffAction = menu.addAction(QStringLiteral("View diff"));
    menu.addSeparator();
    QAction* dropAction = menu.addAction(QStringLiteral("Drop stash…"));
    markDanger(dropAction);

    QAction* chosen = menu.exec(stashList_->viewport()->mapToGlobal(pos));
    if (chosen == nullptr) {
        return;
    }

    if (chosen == applyAction) {
        StashApplyRequest request;
        request.index = stashIndex;
        emit statusMessage(QStringLiteral("Applying stash@{%1}…").arg(stashIndex));
        runWithFeedback_([this, request] { session_->applyStash(request); }, nullptr);
    } else if (chosen == popAction) {
        StashApplyRequest request;
        request.index = stashIndex;
        request.pop = true;
        emit statusMessage(QStringLiteral("Popping stash@{%1}…").arg(stashIndex));
        runWithFeedback_([this, request] { session_->applyStash(request); }, nullptr);
    } else if (chosen == branchAction) {
        const auto nameResult = dialogs::promptText(
            this, QStringLiteral("Create branch from stash"), QStringLiteral("Branch name:"));
        if (!nameResult || nameResult->isEmpty()) {
            return;
        }
        const QString name = *nameResult;
        StashBranchRequest request;
        request.index = stashIndex;
        request.branchName = name.toStdString();
        emit statusMessage(
            QStringLiteral("Creating %1 from stash@{%2}…").arg(name).arg(stashIndex));
        runWithFeedback_([this, request] { session_->branchFromStash(request); }, nullptr);
    } else if (chosen == diffAction) {
        // No standalone Diff page exists yet (Phase 5's job) -- this asks
        // MainWindow to navigate to whichever view currently stands in for
        // it, same as the branch/repo menus' "Repository settings" entry.
        emit diffRequested();
    } else if (chosen == dropAction) {
        const bool confirmed =
            dialogs::confirm(this,
                             QStringLiteral("Drop stash?"),
                             QStringLiteral("This permanently deletes stash@{%1}.").arg(stashIndex),
                             QStringLiteral("Discard"),
                             /*destructive=*/true);
        if (!confirmed) {
            return;
        }
        StashDropRequest request;
        request.index = stashIndex;
        emit statusMessage(QStringLiteral("Dropping stash@{%1}…").arg(stashIndex));
        runWithFeedback_([this, request] { session_->dropStash(request); }, nullptr);
    }
}

}  // namespace gbm
