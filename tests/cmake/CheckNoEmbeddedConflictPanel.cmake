# Design C4: the working copy view must never again embed a
# ConflictResolvePanel of its own (conflictStack_/conflictPanel_,
# maybeAutoShowConflictPanel()'s forced takeover of the diff pane, or
# openConflictResolutionDialog()'s 720x420 modal QDialog). Resolving
# conflicts is exclusively ConflictResolveWindow's job now, reached via
# MainWindow's bannerResolveButton_ or WorkingCopyView::resolveConflictsRequested
# -- see the plan's Context section on why the embedded panel was a UX
# regression (too small, and it could seize the diff pane out from under
# whatever the user was looking at).
#
# A source check rather than a behavioural one, same reasoning as
# CheckBannerLabelNotHidden.cmake: regression-testing this at runtime would
# need a full WorkingCopyView wired to a live RepositorySession with a
# conflict in progress, just to observe that a panel it used to embed is
# gone.

if(NOT SOURCE_DIR)
    message(FATAL_ERROR "CheckNoEmbeddedConflictPanel.cmake requires SOURCE_DIR")
endif()

set(headerFile "${SOURCE_DIR}/src/app/views/pages/WorkingCopyView.h")
set(sourceFile "${SOURCE_DIR}/src/app/views/pages/WorkingCopyView.cpp")
foreach(f headerFile sourceFile)
    if(NOT EXISTS "${${f}}")
        message(FATAL_ERROR "CheckNoEmbeddedConflictPanel.cmake: ${${f}} not found")
    endif()
endforeach()

file(READ "${headerFile}" headerText)
file(READ "${sourceFile}" sourceText)
string(REGEX REPLACE "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/" "" headerText "${headerText}")
string(REGEX REPLACE "//[^\n]*" "" headerText "${headerText}")
string(REGEX REPLACE "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/" "" sourceText "${sourceText}")
string(REGEX REPLACE "//[^\n]*" "" sourceText "${sourceText}")

set(combinedText "${headerText}\n${sourceText}")

foreach(forbidden
    "conflictStack_"
    "conflictPanel_"
    "autoShowSuppressed_"
    "maybeAutoShowConflictPanel"
    "openConflictResolutionDialog"
    "onConflictPanelResolved"
    "onConflictPanelCancelled"
    "workingCopy/autoShowConflictPanel")
    if(combinedText MATCHES "${forbidden}")
        message(FATAL_ERROR
            "'${forbidden}' found in WorkingCopyView.h/.cpp. The working copy "
            "view must not embed a conflict panel of its own -- resolving "
            "conflicts is exclusively ConflictResolveWindow's job (opened via "
            "MainWindow's bannerResolveButton_ or "
            "WorkingCopyView::resolveConflictsRequested).")
    endif()
endforeach()

message(STATUS "WorkingCopyView.h/.cpp no longer embeds a conflict panel of its own")
