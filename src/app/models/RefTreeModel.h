#pragma once

#include "core/git/RefStore.h"

#include <QAbstractItemModel>
#include <QString>

#include <memory>
#include <vector>

namespace gbm {

/// Tree of local branches, remotes and tags.
///
/// Branch names are hierarchical (`feature/auth/login`), so the tree is built by
/// splitting on '/' rather than showing one flat list per ref. On a repository with
/// thousands of stale branches a flat list is unusable, and the hierarchy is what
/// the user already thinks in.
class RefTreeModel : public QAbstractItemModel {
    Q_OBJECT

public:
    enum Roles {
        FullRefNameRole = Qt::UserRole + 1,
        ShortNameRole,
        IsRefRole,  ///< False for grouping nodes such as "feature/".
        IsHeadRole,
        RefKindRole,
        /// True for a top-level section root ("Branches" / "Remotes" / "Tags"),
        /// as opposed to an intermediate slash-separated grouping node such as
        /// "feature/" -- the sidebar delegate needs to tell the two apart to
        /// paint one as an uppercase section header and the other as an
        /// ordinary tree label.
        IsSectionRole,
    };

    explicit RefTreeModel(QObject* parent = nullptr);
    ~RefTreeModel() override;

    QModelIndex index(int row,
                      int column,
                      const QModelIndex& parent = QModelIndex()) const override;
    QModelIndex parent(const QModelIndex& child) const override;
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    int columnCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;

    void setRefs(RefSnapshotPtr refs);

    /// Full ref name for an index, or an empty string for a grouping node.
    QString refNameAt(const QModelIndex& index) const;

private:
    struct Node {
        QString label;
        QString fullName;  ///< Empty for grouping nodes.
        QString shortName;
        RefKind kind = RefKind::Other;
        bool isRef = false;
        bool isHead = false;
        int ahead = 0;
        int behind = 0;
        Node* parent = nullptr;
        std::vector<std::unique_ptr<Node>> children;

        Node* childNamed(const QString& name);
    };

    void rebuild();
    Node* nodeFor(const QModelIndex& index) const;

    RefSnapshotPtr refs_;
    std::unique_ptr<Node> root_;
};

}  // namespace gbm
