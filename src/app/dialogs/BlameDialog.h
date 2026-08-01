#pragma once

#include "core/git/BlameStore.h"

#include <QDialog>
#include <QString>

namespace gbm {

/// Read-only table of `git blame` results for one file, shown once
/// `RepositorySession::blameReady` delivers them.
class BlameDialog : public QDialog {
    Q_OBJECT

public:
    BlameDialog(const QString& path, const BlameResult& result, QWidget* parent = nullptr);
};

}  // namespace gbm
