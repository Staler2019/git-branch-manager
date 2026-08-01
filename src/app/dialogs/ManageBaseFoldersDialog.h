#pragma once

#include "core/cache/RepoIndexDb.h"

#include <QDialog>

#include <vector>

namespace gbm {

class DiscoveryController;

/// Lists every scanned base folder with its depth and enabled state, and
/// lets the user change the depth or remove a folder. Owns its own table and
/// talks straight to `DiscoveryController`; the caller only needs to know
/// whether a rescan is warranted once the dialog closes.
class ManageBaseFoldersDialog : public QDialog {
    Q_OBJECT

public:
    ManageBaseFoldersDialog(DiscoveryController* discovery, QWidget* parent = nullptr);

    /// True if a folder was removed or its depth changed while the dialog was
    /// open -- the caller's cue to start a rescan.
    bool changed() const { return changed_; }

private:
    // Member, not a constructor-local: buttons connected below capture it by
    // reference, and those connections outlive the constructor for as long as
    // the dialog is open.
    std::vector<BaseFolderRecord> folders_;
    bool changed_ = false;
};

}  // namespace gbm
