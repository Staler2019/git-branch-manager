#pragma once

#include "core/git/CommitMeta.h"
#include "core/git/RefStore.h"
#include "core/graph/GraphSnapshot.h"

#include <QAbstractTableModel>
#include <QHash>
#include <QSet>

#include <memory>
#include <vector>

namespace gbm {

class RepositorySession;

/// Table model over a graph snapshot.
///
/// The contract that matters: **`data()` never blocks.** A metadata miss returns a
/// placeholder and schedules a batched fetch; it does not wait for git. With half a
/// million rows, a single synchronous read inside `data()` would be called once per
/// visible cell per frame and the view would crawl.
class CommitListModel : public QAbstractTableModel {
    Q_OBJECT

public:
    enum Column {
        ColumnGraph = 0,
        ColumnSubject,
        ColumnAuthor,
        ColumnDate,
        ColumnShortSha,
        ColumnCount
    };

    /// Roles the graph delegate uses to reach the snapshot without copying it.
    enum Roles {
        RowMetaRole = Qt::UserRole + 1,
        RefsRole,
        ObjectIdRole,
        HasMetadataRole,
    };

    explicit CommitListModel(QObject* parent = nullptr);

    void setSession(RepositorySession* session);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    int columnCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role) const override;

    /// The snapshot the view is currently rendering. Held by shared_ptr, so it
    /// stays valid for the whole frame even if a worker publishes a newer one.
    GraphSnapshotPtr snapshot() const { return snapshot_; }

    RefSnapshotPtr refs() const { return refs_; }

    ObjectId oidAt(int row) const;

    /// Tells the model which rows are on screen, so metadata is fetched for those
    /// (plus a prefetch margin in the scroll direction) and nothing else. Rows the
    /// user never looks at are never read.
    void setVisibleRange(int firstRow, int lastRow);

    /// Installs a snapshot directly, with no session behind it.
    ///
    /// Test seam. It exists so the never-blocking `data()` contract can be verified
    /// against a realistically sized history without spawning git: with no session,
    /// metadata never arrives, which is exactly the worst case the contract is about.
    void setSnapshotForTesting(GraphSnapshotPtr snapshot);

public slots:
    void onGraphUpdated(bool complete);
    void onRefsUpdated();
    void onCommitMetadataReady(const std::vector<CommitMeta>& metadata);

private:
    /// Rows either side of the viewport to prefetch, so scrolling stays ahead of
    /// the reader rather than chasing it.
    static constexpr int kPrefetchMargin = 400;
    /// Bound on the in-memory metadata cache. Roughly 20k commits' worth.
    static constexpr int kMetadataCacheLimit = 20000;

    void scheduleMetadataFetch(int firstRow, int lastRow);
    const CommitMeta* metadataFor(int row) const;

    RepositorySession* session_ = nullptr;
    GraphSnapshotPtr snapshot_;
    RefSnapshotPtr refs_;

    /// oid hex -> metadata. Bounded; trimmed from the far side of the viewport.
    QHash<QString, CommitMeta> metadata_;
    /// Requests already in flight, so a scroll does not re-ask for the same rows.
    QSet<QString> pending_;

    int visibleFirst_ = 0;
    int visibleLast_ = 0;
};

}  // namespace gbm
