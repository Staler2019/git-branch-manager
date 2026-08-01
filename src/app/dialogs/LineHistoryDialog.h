#pragma once

#include "core/git/FileHistoryStore.h"

#include <QDialog>
#include <QString>

#include <vector>

namespace gbm {

/// Read-only diff-per-commit view for a line range in one file, shown once
/// `RepositorySession::lineHistoryReady` delivers the chunks.
class LineHistoryDialog : public QDialog {
    Q_OBJECT

public:
    LineHistoryDialog(const QString& path,
                      const std::vector<LineHistoryChunk>& chunks,
                      QWidget* parent = nullptr);
};

}  // namespace gbm
