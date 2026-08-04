#include "app/models/CommitListModel.h"

#include "app/bridge/RepositorySession.h"
#include "app/bridge/ThemeManager.h"
#include "app/theme/Metrics.h"

#include <QBrush>
#include <QDateTime>
#include <QFont>
#include <QLocale>
#include <QVariant>

#include <algorithm>

namespace gbm {

CommitListModel::CommitListModel(QObject* parent) : QAbstractTableModel(parent) {}

void CommitListModel::setSession(RepositorySession* session) {
    beginResetModel();
    session_ = session;
    snapshot_.reset();
    refs_.reset();
    metadata_.clear();
    pending_.clear();
    visibleFirst_ = 0;
    visibleLast_ = 0;
    mineEmailLower_.clear();
    mineNameLower_.clear();
    endResetModel();
    onEffectiveIdentityUpdated();
}

int CommitListModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) {
        return 0;
    }
    return snapshot_ ? static_cast<int>(snapshot_->rowCount()) : 0;
}

int CommitListModel::columnCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : ColumnCount;
}

ObjectId CommitListModel::oidAt(int row) const {
    if (!snapshot_ || row < 0 || row >= static_cast<int>(snapshot_->oids.size())) {
        return {};
    }
    return snapshot_->oids[static_cast<std::size_t>(row)];
}

bool CommitListModel::isMine(const CommitMeta* meta) const {
    if (meta == nullptr) {
        return false;
    }
    if (!mineEmailLower_.isEmpty() && !meta->author.email.empty()) {
        return QString::fromStdString(meta->author.email).toLower() == mineEmailLower_;
    }
    if (!mineNameLower_.isEmpty() && !meta->author.name.empty()) {
        return QString::fromStdString(meta->author.name).toLower() == mineNameLower_;
    }
    return false;
}

const CommitMeta* CommitListModel::metadataFor(int row) const {
    const ObjectId oid = oidAt(row);
    if (oid.isNull()) {
        return nullptr;
    }
    const auto it = metadata_.constFind(QString::fromStdString(oid.hex()));
    return it == metadata_.constEnd() ? nullptr : &it.value();
}

QVariant CommitListModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || !snapshot_) {
        return {};
    }
    const int row = index.row();
    if (row < 0 || row >= static_cast<int>(snapshot_->rowCount())) {
        return {};
    }

    switch (role) {
        case RowMetaRole:
            // The delegate reads geometry straight from the snapshot; returning the
            // row index avoids copying anything per cell.
            return row;
        case ObjectIdRole:
            return QString::fromStdString(oidAt(row).hex());
        case HasMetadataRole:
            return metadataFor(row) != nullptr;
        case IsMineRole:
            return isMine(metadataFor(row));
        case RefsRole: {
            QVariantList chips;
            if (refs_) {
                if (const auto* atRow = refs_->refsAt(oidAt(row))) {
                    for (const RefInfo* ref : *atRow) {
                        chips << QVariant::fromValue(RefChip{
                            QString::fromStdString(ref->shortName), ref->kind, ref->isHead});
                    }
                }
            }
            return chips;
        }
        default:
            break;
    }

    // Metadata is fetched lazily. A miss must return immediately with a
    // placeholder: blocking here is what would make a 500k-row view unusable.
    const CommitMeta* meta = metadataFor(row);

    if (role == Qt::DisplayRole) {
        switch (index.column()) {
            case ColumnGraph:
                return {};  // Painted by the delegate.
            case ColumnSubject:
                if (meta == nullptr) {
                    return QStringLiteral("…");  // horizontal ellipsis
                }
                return QString::fromStdString(meta->subject);
            case ColumnAuthor:
                return meta == nullptr ? QString() : QString::fromStdString(meta->author.name);
            case ColumnDate: {
                // The commit time comes from the graph snapshot, so the date column
                // is populated even before metadata arrives.
                const auto seconds =
                    static_cast<qint64>(snapshot_->rows[static_cast<std::size_t>(row)].commitTime);
                return QLocale().toString(QDateTime::fromSecsSinceEpoch(seconds),
                                          QLocale::ShortFormat);
            }
            case ColumnShortSha:
                return QString::fromStdString(oidAt(row).shortHex(8));
            default:
                return {};
        }
    }

    if (role == Qt::ToolTipRole && meta != nullptr) {
        QString tip = QString::fromStdString(meta->subject);
        if (!meta->body.empty()) {
            tip += QStringLiteral("\n\n") + QString::fromStdString(meta->body);
        }
        return tip;
    }

    if (role == Qt::TextAlignmentRole && index.column() == ColumnDate) {
        return static_cast<int>(Qt::AlignRight | Qt::AlignVCenter);
    }

    // Author/Date/ShortSha read as metadata rather than content, per
    // docs/design/tokens-reference.md's `.gbm-mono` + secondary-text
    // treatment for exactly this kind of column. Re-derived from
    // ThemeManager on every paint rather than cached, so a theme switch's
    // plain viewport repaint (MainWindow::applyThemeAndRefresh) picks it up
    // with no dataChanged needed -- the same pattern GraphColumnDelegate and
    // RefRowDelegate already rely on.
    switch (index.column()) {
        case ColumnAuthor: {
            const bool mine = isMine(meta);
            if (role == Qt::FontRole) {
                QFont font = ThemeManager::monoFont(kTextXs);
                if (mine) {
                    font.setBold(true);
                }
                return font;
            }
            if (role == Qt::ForegroundRole) {
                return QBrush(ThemeManager::color(mine ? Token::Accent : Token::TextTertiary));
            }
            break;
        }
        case ColumnDate:
        case ColumnShortSha:
            if (role == Qt::FontRole) {
                return ThemeManager::monoFont(kTextXs);
            }
            if (role == Qt::ForegroundRole) {
                return QBrush(ThemeManager::color(Token::TextTertiary));
            }
            break;
        default:
            break;
    }

    return {};
}

QVariant CommitListModel::headerData(int section, Qt::Orientation orientation, int role) const {
    if (orientation != Qt::Horizontal || role != Qt::DisplayRole) {
        return {};
    }
    switch (section) {
        case ColumnGraph:
            return QStringLiteral("Graph");
        case ColumnSubject:
            return QStringLiteral("Subject");
        case ColumnAuthor:
            return QStringLiteral("Author");
        case ColumnDate:
            return QStringLiteral("Date");
        case ColumnShortSha:
            return QStringLiteral("Commit");
        default:
            return {};
    }
}

void CommitListModel::onGraphUpdated(bool complete) {
    if (session_ == nullptr) {
        return;
    }
    auto incoming = session_->graph();
    if (!incoming) {
        return;
    }

    const int oldRows = snapshot_ ? static_cast<int>(snapshot_->rowCount()) : 0;
    const int newRows = static_cast<int>(incoming->rowCount());

    // The common case while streaming is pure growth, which can be reported as an
    // insertion so the view keeps its scroll position and selection.
    if (snapshot_ && newRows >= oldRows && oldRows > 0) {
        if (newRows > oldRows) {
            beginInsertRows(QModelIndex(), oldRows, newRows - 1);
            snapshot_ = std::move(incoming);
            endInsertRows();
        } else {
            snapshot_ = std::move(incoming);
        }
        // Edges and boundary flags for earlier rows can change as parents arrive.
        if (oldRows > 0) {
            emit dataChanged(index(0, 0), index(oldRows - 1, ColumnCount - 1));
        }
    } else {
        beginResetModel();
        snapshot_ = std::move(incoming);
        endResetModel();
    }

    if (complete) {
        // Fetch metadata for whatever is on screen now that rows have settled.
        scheduleMetadataFetch(visibleFirst_, visibleLast_);
    }
}

void CommitListModel::onRefsUpdated() {
    if (session_ == nullptr) {
        return;
    }
    refs_ = session_->refs();
    if (snapshot_ && snapshot_->rowCount() > 0) {
        emit dataChanged(index(0, 0),
                         index(static_cast<int>(snapshot_->rowCount()) - 1, ColumnCount - 1),
                         {RefsRole, Qt::DisplayRole});
    }
}

void CommitListModel::onEffectiveIdentityUpdated() {
    mineEmailLower_.clear();
    mineNameLower_.clear();
    if (session_) {
        if (const EffectiveIdentityPtr identity = session_->effectiveIdentity()) {
            mineEmailLower_ = QString::fromStdString(identity->email).toLower();
            mineNameLower_ = QString::fromStdString(identity->name).toLower();
        }
    }
    if (snapshot_ && snapshot_->rowCount() > 0) {
        emit dataChanged(index(0, 0),
                         index(static_cast<int>(snapshot_->rowCount()) - 1, ColumnCount - 1),
                         {IsMineRole, Qt::FontRole, Qt::ForegroundRole});
    }
}

void CommitListModel::onCommitMetadataReady(const std::vector<CommitMeta>& metadata) {
    if (metadata.empty() || !snapshot_) {
        return;
    }

    int firstChanged = std::numeric_limits<int>::max();
    int lastChanged = -1;

    for (const CommitMeta& meta : metadata) {
        const QString key = QString::fromStdString(meta.oid.hex());
        metadata_.insert(key, meta);
        pending_.remove(key);

        RowId row = 0;
        if (snapshot_->findRow(meta.oid, &row)) {
            firstChanged = std::min(firstChanged, static_cast<int>(row));
            lastChanged = std::max(lastChanged, static_cast<int>(row));
        }
    }

    // Trim the cache from the far side of the viewport, so scrolling back is still
    // cheap while memory stays bounded.
    if (metadata_.size() > kMetadataCacheLimit) {
        const int keepFrom = visibleFirst_ - kPrefetchMargin * 4;
        const int keepTo = visibleLast_ + kPrefetchMargin * 4;
        for (auto it = metadata_.begin(); it != metadata_.end();) {
            RowId row = 0;
            const bool known = snapshot_->findRow(ObjectId::fromHex(it.key().toStdString()), &row);
            if (known && (static_cast<int>(row) < keepFrom || static_cast<int>(row) > keepTo)) {
                it = metadata_.erase(it);
            } else {
                ++it;
            }
            if (metadata_.size() <= kMetadataCacheLimit) {
                break;
            }
        }
    }

    if (lastChanged >= 0) {
        emit dataChanged(index(firstChanged, ColumnSubject), index(lastChanged, ColumnCount - 1));
    }
}

void CommitListModel::setSnapshotForTesting(GraphSnapshotPtr snapshot) {
    beginResetModel();
    snapshot_ = std::move(snapshot);
    metadata_.clear();
    pending_.clear();
    endResetModel();
}

void CommitListModel::setVisibleRange(int firstRow, int lastRow) {
    visibleFirst_ = firstRow;
    visibleLast_ = lastRow;
    scheduleMetadataFetch(firstRow, lastRow);
}

void CommitListModel::scheduleMetadataFetch(int firstRow, int lastRow) {
    if (session_ == nullptr || !snapshot_ || snapshot_->rowCount() == 0) {
        return;
    }

    const int total = static_cast<int>(snapshot_->rowCount());
    const int from = std::max(0, firstRow - kPrefetchMargin);
    const int to = std::min(total - 1, lastRow + kPrefetchMargin);
    if (from > to) {
        return;
    }

    std::vector<ObjectId> wanted;
    wanted.reserve(static_cast<std::size_t>(to - from + 1));
    for (int row = from; row <= to; ++row) {
        const ObjectId oid = oidAt(row);
        if (oid.isNull()) {
            continue;
        }
        const QString key = QString::fromStdString(oid.hex());
        if (metadata_.contains(key) || pending_.contains(key)) {
            continue;
        }
        pending_.insert(key);
        wanted.push_back(oid);
    }

    if (!wanted.empty()) {
        session_->requestCommitMetadata(std::move(wanted));
    }
}

}  // namespace gbm
