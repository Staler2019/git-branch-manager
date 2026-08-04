#pragma once

#include "core/git/RefStore.h"

#include <QDialog>

#include <string>
#include <vector>

class QListWidget;

namespace gbm {

/// Lets the user pick which branches the History graph should be built
/// from. Backed by RepositorySession::setHistoryFilter / HistoryQuery::
/// includeRefs -- both already fully wired to `git rev-list`, this dialog is
/// just the missing UI for it. Nothing checked means "show everything",
/// matching HistoryQuery::includeRefs's own "empty means --all" contract.
class GraphBranchFilterDialog : public QDialog {
    Q_OBJECT

public:
    /// `refs` seeds the checklist (local + remote branches only -- tags
    /// aren't branches); `selected` (a subset of ref full names) pre-checks
    /// whatever filter is already active, so reopening the dialog shows the
    /// current selection instead of resetting it.
    GraphBranchFilterDialog(const RefSnapshot& refs,
                            const std::vector<std::string>& selected,
                            QWidget* parent = nullptr);

    /// Full names of the checked refs. Empty means "show everything".
    std::vector<std::string> selectedRefs() const;

private:
    QListWidget* list_ = nullptr;
};

}  // namespace gbm
