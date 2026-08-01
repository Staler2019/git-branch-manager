#pragma once

#include "core/base/ObjectId.h"
#include "core/git/ops/RebaseOps.h"

#include <QDialog>

#include <memory>
#include <vector>

namespace gbm {

class RepositorySession;

/// Edits the todo list (pick/edit/squash/fixup/drop, and reorder) for an
/// interactive rebase onto `upstream`, then reports it back via `request()`.
/// Requests the plan from `RepositorySession` itself once shown; the caller
/// only needs to start the rebase after `exec()` accepts.
class InteractiveRebaseDialog : public QDialog {
    Q_OBJECT

public:
    InteractiveRebaseDialog(RepositorySession* session,
                            const ObjectId& upstream,
                            QWidget* parent = nullptr);

    /// Valid only after `exec()` returned `QDialog::Accepted` and the todo
    /// list is non-empty.
    RebaseInteractiveRequest request() const;

    bool hasTodoEntries() const;

private:
    ObjectId upstream_;
    std::shared_ptr<std::vector<RebaseTodoEntry>> todo_;
};

}  // namespace gbm
