#include "app/models/RefTreeModel.h"

#include <QFont>
#include <QStringList>

#include <algorithm>
#include <functional>

namespace gbm {

RefTreeModel::Node* RefTreeModel::Node::childNamed(const QString& name) {
    for (auto& child : children) {
        if (child->label == name) {
            return child.get();
        }
    }
    auto created = std::make_unique<Node>();
    created->label = name;
    created->parent = this;
    Node* raw = created.get();
    children.push_back(std::move(created));
    return raw;
}

RefTreeModel::RefTreeModel(QObject* parent) : QAbstractItemModel(parent) {
    root_ = std::make_unique<Node>();
}

RefTreeModel::~RefTreeModel() = default;

void RefTreeModel::setRefs(RefSnapshotPtr refs) {
    beginResetModel();
    refs_ = std::move(refs);
    rebuild();
    endResetModel();
}

void RefTreeModel::rebuild() {
    root_ = std::make_unique<Node>();
    if (!refs_) {
        return;
    }

    // Fixed top-level sections, created only when they have content.
    Node* locals = nullptr;
    Node* remotes = nullptr;
    Node* tags = nullptr;

    for (const RefInfo& ref : refs_->refs) {
        Node* section = nullptr;
        switch (ref.kind) {
            case RefKind::LocalBranch:
                if (locals == nullptr) {
                    locals = root_->childNamed(QStringLiteral("Branches"));
                }
                section = locals;
                break;
            case RefKind::RemoteBranch:
                if (remotes == nullptr) {
                    remotes = root_->childNamed(QStringLiteral("Remotes"));
                }
                section = remotes;
                break;
            case RefKind::Tag:
                if (tags == nullptr) {
                    tags = root_->childNamed(QStringLiteral("Tags"));
                }
                section = tags;
                break;
            default:
                continue;  // Notes and stash are surfaced elsewhere.
        }

        // Split on '/' so `feature/auth/login` nests, rather than producing one
        // very long flat entry among thousands.
        const QString shortName = QString::fromStdString(ref.shortName);
        const QStringList parts = shortName.split(QLatin1Char('/'), Qt::SkipEmptyParts);
        Node* cursor = section;
        for (int i = 0; i < parts.size(); ++i) {
            cursor = cursor->childNamed(parts[i]);
        }

        cursor->fullName = QString::fromStdString(ref.fullName);
        cursor->shortName = shortName;
        cursor->kind = ref.kind;
        cursor->isRef = true;
        cursor->isHead = ref.isHead;
        cursor->ahead = ref.ahead;
        cursor->behind = ref.behind;
    }

    // Stable alphabetical order within each level, with groups before leaves so the
    // hierarchy reads top-down.
    std::function<void(Node*)> sortNode = [&sortNode](Node* node) {
        std::sort(node->children.begin(),
                  node->children.end(),
                  [](const std::unique_ptr<Node>& a, const std::unique_ptr<Node>& b) {
                      if (a->isRef != b->isRef) {
                          return !a->isRef;
                      }
                      return a->label.compare(b->label, Qt::CaseInsensitive) < 0;
                  });
        for (auto& child : node->children) {
            sortNode(child.get());
        }
    };
    sortNode(root_.get());
}

RefTreeModel::Node* RefTreeModel::nodeFor(const QModelIndex& index) const {
    if (!index.isValid()) {
        return root_.get();
    }
    return static_cast<Node*>(index.internalPointer());
}

QModelIndex RefTreeModel::index(int row, int column, const QModelIndex& parent) const {
    if (column != 0) {
        return {};
    }
    Node* parentNode = nodeFor(parent);
    if (parentNode == nullptr || row < 0 || row >= static_cast<int>(parentNode->children.size())) {
        return {};
    }
    return createIndex(row, column, parentNode->children[static_cast<std::size_t>(row)].get());
}

QModelIndex RefTreeModel::parent(const QModelIndex& child) const {
    Node* node = nodeFor(child);
    if (node == nullptr || node->parent == nullptr || node->parent == root_.get()) {
        return {};
    }
    Node* grandparent = node->parent->parent;
    if (grandparent == nullptr) {
        return {};
    }
    const auto at = std::find_if(
        grandparent->children.begin(),
        grandparent->children.end(),
        [node](const std::unique_ptr<Node>& candidate) { return candidate.get() == node->parent; });
    if (at == grandparent->children.end()) {
        return {};
    }
    return createIndex(static_cast<int>(at - grandparent->children.begin()), 0, node->parent);
}

int RefTreeModel::rowCount(const QModelIndex& parent) const {
    Node* node = nodeFor(parent);
    return node == nullptr ? 0 : static_cast<int>(node->children.size());
}

int RefTreeModel::columnCount(const QModelIndex& parent) const {
    Q_UNUSED(parent);
    return 1;
}

QVariant RefTreeModel::data(const QModelIndex& index, int role) const {
    Node* node = nodeFor(index);
    if (node == nullptr || node == root_.get()) {
        return {};
    }

    switch (role) {
        case Qt::DisplayRole: {
            QString label = node->label;
            if (node->isRef && (node->ahead > 0 || node->behind > 0)) {
                label += QStringLiteral("  ");
                if (node->ahead > 0) {
                    label += QStringLiteral("↑%1").arg(node->ahead);
                }
                if (node->behind > 0) {
                    label += QStringLiteral("↓%1").arg(node->behind);
                }
            }
            return label;
        }
        case Qt::FontRole:
            if (node->isHead) {
                QFont font;
                font.setBold(true);
                return font;
            }
            return {};
        case FullRefNameRole:
            return node->fullName;
        case ShortNameRole:
            return node->shortName;
        case IsRefRole:
            return node->isRef;
        case IsHeadRole:
            return node->isHead;
        case RefKindRole:
            return static_cast<int>(node->kind);
        case IsSectionRole:
            return !node->isRef && node->parent == root_.get();
        default:
            return {};
    }
}

QString RefTreeModel::refNameAt(const QModelIndex& index) const {
    Node* node = nodeFor(index);
    return node == nullptr || !node->isRef ? QString() : node->shortName;
}

}  // namespace gbm
