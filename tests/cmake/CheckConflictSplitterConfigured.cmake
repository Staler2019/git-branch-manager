# Pins two source-shape facts about ConflictResolvePanel.cpp's pane
# splitter, without needing a runtime harness (see
# CheckBannerLabelNotHidden.cmake for the precedent):
#
# 1. regionStrip_ (the region-navigation controls) must never again be
#    inserted into a pane container's own layout. That's what inflated the
#    middle pane's minimumSizeHint far past its siblings' and made the
#    splitter refuse to let it shrink -- see ConflictUiTest.cpp's
#    middlePaneIsNotSpeciallyWide() for the runtime half of this regression
#    guard. This half exists because the core-only / asan / tsan presets
#    never build Qt at all, so they cannot run the Qt test; a plain text
#    check still gates them.
# 2. panesSplitter_ must carry its house configuration (setHandleWidth,
#    setChildrenCollapsible(false)) -- every other splitter in this app has
#    it (see WorkingCopyView.cpp, SidebarPanel.cpp); this one was the sole
#    exception before the fix.

if(NOT SOURCE_DIR)
    message(FATAL_ERROR "CheckConflictSplitterConfigured.cmake requires SOURCE_DIR")
endif()

set(panelFile "${SOURCE_DIR}/src/app/views/ConflictResolvePanel.cpp")
if(NOT EXISTS "${panelFile}")
    message(FATAL_ERROR "CheckConflictSplitterConfigured.cmake: ${panelFile} not found")
endif()

file(READ "${panelFile}" text)
string(REGEX REPLACE "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/" "" text "${text}")
string(REGEX REPLACE "//[^\n]*" "" text "${text}")

# middleContainer->layout() is the only layout regionStrip_ may ever have
# been inserted into pre-fix; catching insertWidget on any pane container's
# layout (they're all built the same way in makePane()) is the general form
# of "don't put it back inside a pane".
if(text MATCHES "->layout\\(\\)\\)->insertWidget\\([^,]*,[ \t\r\n]*regionStrip_")
    message(FATAL_ERROR
        "regionStrip_ is inserted into a pane container's layout in "
        "ConflictResolvePanel.cpp. This inflates that pane's minimumSizeHint "
        "and breaks the splitter's ability to shrink it -- host the strip in "
        "a full-width row above panesSplitter_ instead.")
endif()

if(NOT text MATCHES "panesSplitter_->setChildrenCollapsible\\([ \t]*false[ \t]*\\)")
    message(FATAL_ERROR
        "panesSplitter_->setChildrenCollapsible(false) not found in "
        "ConflictResolvePanel.cpp -- without it, panes can be dragged to "
        "zero width and never recover.")
endif()

if(NOT text MATCHES "panesSplitter_->setHandleWidth\\(")
    message(FATAL_ERROR
        "panesSplitter_->setHandleWidth(...) not found in "
        "ConflictResolvePanel.cpp -- every other splitter in this app sets "
        "an explicit handle width; this one should too.")
endif()

message(STATUS "ConflictResolvePanel.cpp's pane splitter carries its house configuration")
