# Fails if WorkingCopyView::errorOccurred is wired straight to showError()
# without first checking armedFeedbackHandlers_.
#
# A source check rather than a behavioural one, and that is the point (see
# CheckNoDuplicateRefRefresh.cmake for the same rationale). The bug this pins:
# WorkingCopyView keeps a permanent connection to workingCopyOperationFinished
# and pops a QMessageBox::Critical for *any* failure, even for operations it
# did not initiate -- e.g. a sidebar branch delete. runWithFeedback() and
# armWorkingCopyChoiceHandler() also listen, one-shot, and pop their own
# dialog for the same outcome. The result was two "Git reported an error"
# boxes back to back for a single failed `git branch -d`. Reproducing that at
# runtime needs a live QApplication and two connected signal paths racing each
# other -- an async harness this repository does not have -- so this instead
# asserts the ownership guard is present in the source.

if(NOT SOURCE_DIR)
    message(FATAL_ERROR "CheckSingleErrorDialogOwner.cmake requires SOURCE_DIR")
endif()

set(main_window_cpp "${SOURCE_DIR}/src/app/views/MainWindow.cpp")
set(main_window_h "${SOURCE_DIR}/src/app/views/MainWindow.h")

if(NOT EXISTS "${main_window_cpp}")
    message(FATAL_ERROR "Expected to find ${main_window_cpp}")
endif()
if(NOT EXISTS "${main_window_h}")
    message(FATAL_ERROR "Expected to find ${main_window_h}")
endif()

file(READ "${main_window_cpp}" cpp_text)
file(READ "${main_window_h}" h_text)

# Comments stripped first, same greedy-safe pattern as
# CheckNoDuplicateRefRefresh.cmake -- this file's own doc comments name
# armedFeedbackHandlers_ in prose and would otherwise trip the check.
string(REGEX REPLACE "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/" "" cpp_text "${cpp_text}")
string(REGEX REPLACE "//[^\n]*" "" cpp_text "${cpp_text}")

set(failures "")

# The counter must exist as a member.
if(NOT h_text MATCHES "armedFeedbackHandlers_")
    list(APPEND failures "MainWindow.h no longer declares armedFeedbackHandlers_")
endif()

# runWithFeedback() and armWorkingCopyChoiceHandler() must both increment it
# before arming their one-shot connection, and decrement it once their
# connection fires (each disconnects itself with QObject::disconnect(*connection)
# immediately beforehand, so that call is the anchor to search near).
if(NOT cpp_text MATCHES "\\+\\+armedFeedbackHandlers_")
    list(APPEND failures "no ++armedFeedbackHandlers_ found -- a feedback handler must arm the counter when it connects")
endif()
if(NOT cpp_text MATCHES "QObject::disconnect\\(\\*connection\\);[ \t\r\n]*--armedFeedbackHandlers_")
    list(APPEND failures "no --armedFeedbackHandlers_ immediately after QObject::disconnect(*connection) -- the counter must be released as soon as a one-shot handler fires, in every runWithFeedback()/armWorkingCopyChoiceHandler() lambda")
endif()

# The errorOccurred connection must check the counter before calling
# showError(); otherwise it duplicates whatever runWithFeedback()/
# armWorkingCopyChoiceHandler() already shows for the same outcome. A fixed
# window rather than brace-matching: CMake's regex engine has no recursion, so
# capturing "everything between this connect()'s matched braces" cannot be
# expressed when the lambda body itself contains a nested if-block's braces --
# the greedy [^{}]* would just backtrack to the nearest unrelated brace pair
# anywhere later in the file. A window sized to comfortably hold this one
# lambda is a robust enough proxy for "the same handler".
string(FIND "${cpp_text}" "WorkingCopyView::errorOccurred" error_occurred_pos)
if(error_occurred_pos EQUAL -1)
    list(APPEND failures "could not locate the WorkingCopyView::errorOccurred connection in MainWindow.cpp to inspect")
else()
    string(SUBSTRING "${cpp_text}" ${error_occurred_pos} 700 handler_window)
    string(FIND "${handler_window}" "armedFeedbackHandlers_" guard_pos)
    string(FIND "${handler_window}" "showError(summary" show_error_pos)
    if(show_error_pos EQUAL -1)
        list(APPEND failures "expected to find a showError(summary, ...) call within 700 characters of the WorkingCopyView::errorOccurred connection")
    elseif(guard_pos EQUAL -1 OR guard_pos GREATER show_error_pos)
        list(APPEND failures "WorkingCopyView::errorOccurred handler calls showError() without checking armedFeedbackHandlers_ first -- this duplicates the dialog runWithFeedback()/armWorkingCopyChoiceHandler() already shows")
    endif()
endif()

if(failures)
    string(REPLACE ";" "\n  - " pretty "${failures}")
    message(FATAL_ERROR "Single-error-dialog-owner invariant violated:\n  - ${pretty}")
endif()

message(STATUS "MainWindow's feedback-handler ownership guard is in place")
