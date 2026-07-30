#include "app/models/RepoListModel.h"

#include <QDateTime>
#include <QFont>

#include <algorithm>

namespace gbm {

namespace {

QString kindLabel(RepoKind kind) {
    switch (kind) {
        case RepoKind::Bare:
            return QStringLiteral("bare");
        case RepoKind::LinkedWorktree:
            return QStringLiteral("worktree");
        case RepoKind::Submodule:
            return QStringLiteral("submodule");
        case RepoKind::Normal:
            return {};
        case RepoKind::NotARepo:
            return {};
    }
    return {};
}

}  // namespace

RepoListModel::RepoListModel(QObject* parent) : QAbstractTableModel(parent) {}

int RepoListModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : static_cast<int>(repos_.size());
}

int RepoListModel::columnCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : ColumnCount;
}

const RepoRecord* RepoListModel::repoAt(int row) const {
    if (row < 0 || row >= static_cast<int>(repos_.size())) {
        return nullptr;
    }
    return &repos_[static_cast<std::size_t>(row)];
}

QVariant RepoListModel::data(const QModelIndex& index, int role) const {
    const RepoRecord* repo = repoAt(index.row());
    if (repo == nullptr) {
        return {};
    }
    const auto probeIt = probes_.constFind(static_cast<qint64>(repo->id));
    const RepoProbe* probe = probeIt == probes_.constEnd() ? nullptr : &probeIt.value();

    switch (role) {
        case PathRole:
            return QString::fromStdString(repo->workDir.empty() ? repo->gitDir : repo->workDir);
        case RepoIdRole:
            return static_cast<qint64>(repo->id);
        case IsStaleRole:
            // No probe yet means the detail columns are showing cached or unknown
            // values; the view dims them rather than implying they are current.
            return probe == nullptr;
        default:
            break;
    }

    if (role == Qt::DisplayRole) {
        switch (index.column()) {
            case ColumnName: {
                QString name = QString::fromStdString(repo->name);
                const QString kind = kindLabel(repo->kind);
                if (!kind.isEmpty()) {
                    name += QStringLiteral(" (") + kind + QStringLiteral(")");
                }
                if (repo->missingSince.has_value()) {
                    name += QStringLiteral("  — missing");
                }
                return name;
            }
            case ColumnBranch:
                if (probe == nullptr || probe->headRef.empty()) {
                    return QString();
                }
                return QString::fromStdString(probe->headRef);
            case ColumnStatus: {
                if (probe == nullptr) {
                    return QString();
                }
                QStringList parts;
                if (probe->ahead > 0) {
                    parts << QStringLiteral("↑%1").arg(probe->ahead);
                }
                if (probe->behind > 0) {
                    parts << QStringLiteral("↓%1").arg(probe->behind);
                }
                // -1 means "not probed yet", which is different from "clean".
                if (probe->dirtyFiles > 0) {
                    parts << QStringLiteral("%1 changed").arg(probe->dirtyFiles);
                }
                if (probe->inProgressFlags != 0) {
                    parts << QStringLiteral("operation in progress");
                }
                return parts.join(QStringLiteral("  "));
            }
            case ColumnPath:
                return QString::fromStdString(repo->workDir.empty() ? repo->gitDir : repo->workDir);
            default:
                return {};
        }
    }

    if (role == Qt::ForegroundRole && probe == nullptr && index.column() != ColumnName) {
        return QVariant();  // Left to the stylesheet; the view dims stale rows.
    }

    if (role == Qt::ToolTipRole) {
        QString tip = QString::fromStdString(repo->gitDir);
        if (probe != nullptr && probe->probedAt > 0) {
            tip += QStringLiteral("\nLast checked: ") +
                   QDateTime::fromSecsSinceEpoch(probe->probedAt).toString(Qt::TextDate);
        } else {
            tip += QStringLiteral("\nNot yet checked");
        }
        return tip;
    }

    return {};
}

QVariant RepoListModel::headerData(int section, Qt::Orientation orientation, int role) const {
    if (orientation != Qt::Horizontal || role != Qt::DisplayRole) {
        return {};
    }
    switch (section) {
        case ColumnName:
            return QStringLiteral("Repository");
        case ColumnBranch:
            return QStringLiteral("Branch");
        case ColumnStatus:
            return QStringLiteral("Status");
        case ColumnPath:
            return QStringLiteral("Location");
        default:
            return {};
    }
}

void RepoListModel::setRepos(std::vector<RepoRecord> repos) {
    beginResetModel();
    repos_ = std::move(repos);
    endResetModel();
}

void RepoListModel::appendRepos(const std::vector<RepoRecord>& repos) {
    if (repos.empty()) {
        return;
    }
    // Discovered repositories can duplicate rows already loaded from the cache, so
    // merge by git dir rather than blindly appending.
    std::vector<RepoRecord> fresh;
    for (const RepoRecord& incoming : repos) {
        const auto existing =
            std::find_if(repos_.begin(), repos_.end(), [&incoming](const RepoRecord& known) {
                return known.gitDir == incoming.gitDir;
            });
        if (existing == repos_.end()) {
            fresh.push_back(incoming);
        } else {
            *existing = incoming;
        }
    }

    if (!fresh.empty()) {
        const int first = static_cast<int>(repos_.size());
        beginInsertRows(QModelIndex(), first, first + static_cast<int>(fresh.size()) - 1);
        for (RepoRecord& record : fresh) {
            repos_.push_back(std::move(record));
        }
        endInsertRows();
    }
    if (!repos_.empty()) {
        emit dataChanged(index(0, 0), index(static_cast<int>(repos_.size()) - 1, ColumnCount - 1));
    }
}

void RepoListModel::setProbe(std::int64_t repoId, const RepoProbe& probe) {
    probes_.insert(static_cast<qint64>(repoId), probe);
    for (std::size_t row = 0; row < repos_.size(); ++row) {
        if (repos_[row].id == repoId) {
            emit dataChanged(index(static_cast<int>(row), 0),
                             index(static_cast<int>(row), ColumnCount - 1));
            return;
        }
    }
}

void RepoListModel::clear() {
    beginResetModel();
    repos_.clear();
    probes_.clear();
    endResetModel();
}

}  // namespace gbm
