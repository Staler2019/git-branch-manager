#pragma once

#include <QWidget>

namespace gbm {

/// Placeholder for the design's Repository Settings tab (identity overrides,
/// performance/pagination settings). Nothing in the current app builds a
/// distinct "repository settings" surface yet -- that is Phase 6's job, not
/// this decomposition phase's -- so this hosts only an honest placeholder
/// label rather than inventing new settings UI.
class RepositoryPage : public QWidget {
    Q_OBJECT

public:
    explicit RepositoryPage(QWidget* parent = nullptr);
};

}  // namespace gbm
