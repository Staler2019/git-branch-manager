#pragma once

#include "core/cache/RepoIndexDb.h"

#include <QAbstractTableModel>
#include <QHash>

#include <vector>

namespace gbm {

/// The repository list, populated from the SQLite cache.
///
/// This model is why startup is fast: it is filled entirely from the cache with
/// **zero filesystem access**, so the window paints immediately even with hundreds
/// of repositories across several base folders. Per-row detail (current branch,
/// ahead/behind, dirty count) comes from the stored probe and is rendered dimmed
/// until it has been revalidated for rows the user can actually see.
class RepoListModel : public QAbstractTableModel {
    Q_OBJECT

public:
    enum Column { ColumnName = 0, ColumnBranch, ColumnStatus, ColumnPath, ColumnCount };

    enum Roles {
        PathRole = Qt::UserRole + 1,
        RepoIdRole,
        IsStaleRole,
        KindRole,    ///< int(RepoKind) -- which icon SidebarRowDelegate picks.
        AheadRole,   ///< int, 0 if no probe yet.
        BehindRole,  ///< int, 0 if no probe yet.
    };

    explicit RepoListModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    int columnCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role) const override;

    void setRepos(std::vector<RepoRecord> repos);

    /// Appends a batch found by a running scan, so rows appear progressively.
    void appendRepos(const std::vector<RepoRecord>& repos);

    void setProbe(std::int64_t repoId, const RepoProbe& probe);

    const RepoRecord* repoAt(int row) const;

    void clear();

private:
    std::vector<RepoRecord> repos_;
    QHash<qint64, RepoProbe> probes_;
};

}  // namespace gbm
