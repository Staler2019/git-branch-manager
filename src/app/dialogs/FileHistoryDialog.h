#pragma once

#include "core/git/FileHistoryStore.h"

#include <QDialog>
#include <QString>

#include <vector>

namespace gbm {

/// Read-only table of the commits that touched one file, shown once
/// `RepositorySession::fileHistoryReady` delivers them.
class FileHistoryDialog : public QDialog {
    Q_OBJECT

public:
    FileHistoryDialog(const QString& path,
                      const std::vector<FileHistoryEntry>& entries,
                      QWidget* parent = nullptr);
};

}  // namespace gbm
