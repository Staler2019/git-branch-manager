#pragma once

#include "core/git/OperationRunner.h"

#include <functional>

namespace gbm {

/// Mirrors `MainWindow::runWithFeedback`'s signature. Extracted dialogs that
/// submit an operation (stash apply, submodule update, bisect mark, ...) take
/// one of these instead of duplicating MainWindow's outcome handling (status
/// text, error dialog, or a confirm-then-retry prompt per recoverable
/// choice): the caller passes its own `runWithFeedback` bound to `this`, so
/// the dialog reports results exactly the way MainWindow always has.
using RunWithFeedbackFn = std::function<void(std::function<void()> submit,
                                             std::function<void(OperationChoice::Kind)> onChoice)>;

}  // namespace gbm
