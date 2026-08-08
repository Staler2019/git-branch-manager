# Fails if MainWindow.cpp ever explicitly hides bannerLabel_ again.
#
# A source check rather than a behavioural one, and that is the point (see
# CheckNoDuplicateRefRefresh.cmake for the precedent). Regression-testing this
# at runtime would mean instantiating a full MainWindow -- pulling in
# WorkingCopyView, every dialog and panel, and a RepositorySession backed by a
# real repository with a conflict in progress -- just to observe one label's
# visibility. bannerRow_->setVisible(false) (the row, not the label) a few
# lines later is the legitimate initial-hide: Qt keeps a child that was never
# explicitly hidden in sync with its ancestor's visibility, so hiding the row
# is enough. Explicitly hiding the label too breaks that sync permanently --
# nothing ever calls bannerLabel_->setVisible(true), so the banner text stays
# blank forever. See issue #20.

if(NOT SOURCE_DIR)
    message(FATAL_ERROR "CheckBannerLabelNotHidden.cmake requires SOURCE_DIR")
endif()

set(mainWindowFile "${SOURCE_DIR}/src/app/views/MainWindow.cpp")
if(NOT EXISTS "${mainWindowFile}")
    message(FATAL_ERROR "CheckBannerLabelNotHidden.cmake: ${mainWindowFile} not found")
endif()

file(READ "${mainWindowFile}" text)
string(REGEX REPLACE "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/" "" text "${text}")
string(REGEX REPLACE "//[^\n]*" "" text "${text}")

if(text MATCHES "bannerLabel_->setVisible\\([ \t]*false[ \t]*\\)")
    message(FATAL_ERROR
        "bannerLabel_->setVisible(false) found in MainWindow.cpp. Qt does not "
        "re-show a child that was explicitly hidden when its ancestor becomes "
        "visible again, so this permanently blanks the state banner's text -- "
        "see issue #20. Hide bannerRow_ (the row) instead, and leave "
        "bannerLabel_'s visibility to follow its parent.")
endif()

message(STATUS "bannerLabel_ is never explicitly hidden in MainWindow.cpp")
