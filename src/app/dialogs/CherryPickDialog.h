#pragma once

#include "core/base/ObjectId.h"

#include <QDialog>
#include <QStringList>

#include <vector>

namespace gbm {

/// Confirms the ordered list of commits about to be cherry-picked onto the
/// current branch. Purely a confirmation -- `commits` is already computed by
/// the caller and is only redisplayed here for review.
class CherryPickDialog : public QDialog {
    Q_OBJECT

public:
    CherryPickDialog(const std::vector<ObjectId>& commits,
                     const QStringList& subjects,
                     QWidget* parent = nullptr);
};

}  // namespace gbm
